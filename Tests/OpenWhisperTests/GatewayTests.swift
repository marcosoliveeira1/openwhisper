import Foundation
import Testing

@testable import OpenWhisper

/// Intercepts URLSession traffic for gateway tests.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: GatewayTestError.noHandler)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum GatewayTestError: Error {
    case noHandler
}

/// URLSession may hand the mock protocol a stream instead of httpBody.
private func httpBodyData(_ request: URLRequest) -> Data? {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

/// Locked box for observing the intercepted request across the
/// URLSession thread boundary.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?
    var request: URLRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func chatResponse(content: String) -> Data {
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return """
    {"choices": [{"message": {"content": "\(escaped)"}}]}
    """.data(using: .utf8)!
}

/// Runs `body` with gateway prefs swapped in, restoring the real values after
/// (gateway tests must not leak into the dev machine's UserDefaults).
private func withGateway(
    _ provider: AIProvider,
    config: GatewayConfig? = nil,
    _ body: () async throws -> Void
) async rethrows {
    let defaults = UserDefaults.standard
    let previousProvider = defaults.string(forKey: "aiProvider")
    var previous: [String: String?] = [:]
    for p in AIProvider.allCases {
        for key in ["gatewayBaseURL_\(p.rawValue)", "gatewayKey_\(p.rawValue)", "gatewayModel_\(p.rawValue)"] {
            previous[key] = defaults.string(forKey: key)
        }
    }
    defaults.set(provider.rawValue, forKey: "aiProvider")
    if let config {
        defaults.set(config.baseURL, forKey: "gatewayBaseURL_\(provider.rawValue)")
        defaults.set(config.apiKey, forKey: "gatewayKey_\(provider.rawValue)")
        defaults.set(config.model, forKey: "gatewayModel_\(provider.rawValue)")
    }
    defer {
        if let previousProvider {
            defaults.set(previousProvider, forKey: "aiProvider")
        } else {
            defaults.removeObject(forKey: "aiProvider")
        }
        for (key, value) in previous {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        MockURLProtocol.handler = nil
    }
    try await body()
}

@Suite(.serialized) struct GatewayTests {
    /// Shared prefs + static handler: this suite runs serially so gateway
    /// tests never race each other (no other suite touches these).
    private let config = GatewayConfig(
        baseURL: "https://api.groq.com/openai/v1", apiKey: "test-key", model: "test-model"
    )

    @Test func presets() {
        #expect(AIProvider.apple.isLocal)
        #expect(!AIProvider.openRouter.isLocal)
        #expect(AIProvider.openRouter.defaultBaseURL == "https://openrouter.ai/api/v1")
        #expect(AIProvider.groq.defaultBaseURL == "https://api.groq.com/openai/v1")
        #expect(AIProvider.openCode.defaultBaseURL == nil)
        #expect(AIProvider.openRouter.defaultModel == "openai/gpt-4o-mini")
        #expect(!AIProvider.groq.defaultModel.isEmpty)
        #expect(AIProvider.openCode.defaultModel.isEmpty)
        #expect(AIProvider.openRouter.extraHeaders["X-Title"] == "OpenWhisper")
        #expect(AIProvider.groq.extraHeaders.isEmpty)
    }

    @Test func storeFallsBackToPresets() async {
        await withGateway(.groq) {
            #expect(GatewayStore.provider() == .groq)
            let config = GatewayStore.config(for: .groq)
            #expect(config.baseURL == "https://api.groq.com/openai/v1")
            #expect(!config.model.isEmpty)
            #expect(config.apiKey.isEmpty)
        }
    }

    @Test func storeRoundTripsOverrides() async {
        await withGateway(.openCode, config: GatewayConfig(
            baseURL: "https://example.com/v1", apiKey: "sek", model: "m1"
        )) {
            #expect(GatewayStore.provider() == .openCode)
            #expect(GatewayStore.config(for: .openCode) == GatewayConfig(
                baseURL: "https://example.com/v1", apiKey: "sek", model: "m1"
            ))
        }
    }

    @Test func defaultProviderIsApple() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "aiProvider")
        defer {
            if let previous {
                defaults.set(previous, forKey: "aiProvider")
            } else {
                defaults.removeObject(forKey: "aiProvider")
            }
        }
        defaults.removeObject(forKey: "aiProvider")
        #expect(GatewayStore.provider() == .apple)
    }

    @Test func sendsCompletionsRequestShape() async throws {
        let box = RequestBox()
        MockURLProtocol.handler = { request in
            box.request = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, chatResponse(content: "ok"))
        }
        let polisher = HTTPChatPolisher(config: config, session: mockSession())
        let polished = try await polisher.polish("texto")
        #expect(polished == "ok")

        let request = try #require(box.request)
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(httpBodyData(request))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "test-model")
        #expect(json["temperature"] as? Double == 0)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["role"] == "user")
        #expect(messages[1]["content"]?.contains("texto") == true)
    }

    @Test func returnsCleanedContent() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, chatResponse(content: "\"Fazer deploy.\""))
        }
        let polisher = HTTPChatPolisher(config: config, session: mockSession())
        let cleaned = try await polisher.polish("fazer deploi.")
        #expect(cleaned == "Fazer deploy.")
    }

    @Test func httpErrorSurfacesStatus() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("bad key".utf8))
        }
        let polisher = HTTPChatPolisher(config: config, session: mockSession())
        await #expect(throws: PolishError.failed("HTTP 401 bad key")) {
            try await polisher.polish("texto")
        }
    }

    @Test func invalidJSONThrows() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }
        let polisher = HTTPChatPolisher(config: config, session: mockSession())
        await #expect(throws: PolishError.failed("resposta JSON inválida do gateway")) {
            try await polisher.polish("texto")
        }
    }

    @Test func implausibleOutputRejected() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, chatResponse(content: "Como posso ajudar você hoje com muitas palavras extras?"))
        }
        let polisher = HTTPChatPolisher(config: config, session: mockSession())
        await #expect(throws: PolishError.failed("resposta inconsistente do gateway")) {
            try await polisher.polish("alô")
        }
    }

    @Test func missingKeyIsUnavailable() async {
        let noKey = GatewayConfig(baseURL: config.baseURL, apiKey: "  ", model: config.model)
        let polisher = HTTPChatPolisher(config: noKey, session: mockSession())
        #expect(!polisher.isAvailable)
        #expect(polisher.availabilityMessage == "Informe a chave API em Configurações")
        await #expect(throws: PolishError.unavailable("Informe a chave API em Configurações")) {
            try await polisher.polish("texto")
        }
    }

    @Test func badBaseURLIsUnavailable() {
        let bad = GatewayConfig(baseURL: "notaurl", apiKey: "k", model: "m")
        #expect(HTTPChatPolisher(config: bad).availabilityMessage == "Informe a URL base do gateway em Configurações")
    }

    @Test func appleWithoutBackendIsUnavailable() async {
        await withGateway(.apple) {
            let router = RoutingPolisher(apple: nil, session: mockSession())
            #expect(!router.isAvailable)
            #expect(router.availabilityMessage == "Limpeza com IA requer macOS 26 com Apple Intelligence")
        }
    }

    @Test func appleDelegatesToBackend() async throws {
        try await withGateway(.apple) {
            let mock = MockPolisher()
            mock.result = "limpo"
            let router = RoutingPolisher(apple: mock, session: mockSession())
            #expect(router.isAvailable)
            let cleaned = try await router.polish("sujo.")
            #expect(cleaned == "limpo")
            #expect(mock.polishedInputs == ["sujo."])
        }
    }

    @Test func remoteDelegatesToHTTPGateway() async throws {
        try await withGateway(.groq, config: GatewayConfig(
            baseURL: "https://api.groq.com/openai/v1", apiKey: "k", model: "m"
        )) {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, chatResponse(content: "limpo via groq."))
            }
            let router = RoutingPolisher(apple: nil, session: mockSession())
            #expect(router.isAvailable)
            let cleaned = try await router.polish("texto sujo aqui.")
            #expect(cleaned == "limpo via groq.")
        }
    }

    @Test func remoteWithoutKeyIsUnavailable() async {
        await withGateway(.openRouter) {
            let router = RoutingPolisher(apple: nil, session: mockSession())
            #expect(!router.isAvailable)
            #expect(router.availabilityMessage == "Informe a chave API em Configurações")
        }
    }
}
