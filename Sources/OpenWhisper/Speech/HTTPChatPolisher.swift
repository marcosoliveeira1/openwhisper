import Foundation

/// OpenAI-compatible chat-completions polisher (OpenRouter, Groq, OpenCode,
/// or any gateway with the same shape). Reuses the shared prompt, output
/// cleaning, and plausibility guard — only the transport differs from Apple.
final class HTTPChatPolisher: TextPolisher, Sendable {
    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private let config: GatewayConfig
    private let extraHeaders: [String: String]
    private let session: URLSession

    init(config: GatewayConfig, extraHeaders: [String: String] = [:], session: URLSession = .shared) {
        self.config = config
        self.extraHeaders = extraHeaders
        self.session = session
    }

    var isAvailable: Bool { availabilityMessage == nil }

    var availabilityMessage: String? {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, URL(string: base)?.scheme?.hasPrefix("http") == true else {
            return "Informe a URL base do gateway em Configurações"
        }
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Informe a chave API em Configurações"
        }
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Informe o modelo em Configurações"
        }
        return nil
    }

    func polish(_ text: String) async throws -> String {
        if let reason = availabilityMessage {
            throw PolishError.unavailable(reason)
        }
        let base = config.baseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else {
            throw PolishError.failed("URL base inválida")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: config.model,
            messages: [
                ChatMessage(role: "system", content: PolishPrompt.instructions),
                ChatMessage(role: "user", content: PolishPrompt.prompt(for: text)),
            ],
            temperature: 0
        ))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PolishError.failed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PolishError.failed("resposta inválida do gateway")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw PolishError.failed("HTTP \(http.statusCode) \(snippet)".trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw PolishError.failed("resposta JSON inválida do gateway")
        }
        let rawContent = decoded.choices.first?.message.content ?? ""
        let cleaned = PolishPrompt.clean(rawContent)
        guard !cleaned.isEmpty else {
            throw PolishError.failed("resposta vazia do gateway")
        }
        guard PolishPrompt.isPlausible(cleaned, for: text) else {
            throw PolishError.failed("resposta inconsistente do gateway")
        }
        return cleaned
    }
}

/// Routes to the Settings-selected backend at call time (no restart needed
/// when the user switches provider). Apple backend is nil on OS versions
/// without FoundationModels.
final class RoutingPolisher: TextPolisher, Sendable {
    private struct Unavailable: TextPolisher, Sendable {
        let reason: String
        var isAvailable: Bool { false }
        var availabilityMessage: String? { reason }
        func polish(_ text: String) async throws -> String {
            throw PolishError.unavailable(reason)
        }
    }

    private let apple: (any TextPolisher)?
    private let session: URLSession

    init(apple: (any TextPolisher)?, session: URLSession = .shared) {
        self.apple = apple
        self.session = session
    }

    private func backend() -> any TextPolisher {
        switch GatewayStore.provider() {
        case .apple:
            return apple ?? Unavailable(reason: "Limpeza com IA requer macOS 26 com Apple Intelligence")
        case .openRouter, .groq, .openCode:
            let provider = GatewayStore.provider()
            return HTTPChatPolisher(
                config: GatewayStore.config(for: provider),
                extraHeaders: provider.extraHeaders,
                session: session
            )
        }
    }

    var isAvailable: Bool { backend().isAvailable }
    var availabilityMessage: String? { backend().availabilityMessage }

    func polish(_ text: String) async throws -> String {
        try await backend().polish(text)
    }
}
