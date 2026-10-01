import Foundation

/// AI backend for transcript cleanup. Apple runs on-device (zero deps);
/// the rest are OpenAI-compatible `POST {baseURL}/chat/completions`
/// gateways configured in Settings.
enum AIProvider: String, CaseIterable, Sendable {
    case apple
    case openRouter
    case groq
    case openCode

    var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .openRouter: "OpenRouter"
        case .groq: "Groq"
        case .openCode: "OpenCode"
        }
    }

    var isLocal: Bool { self == .apple }

    /// Preset endpoint. Nil for OpenCode — the user fills base URL + bearer.
    var defaultBaseURL: String? {
        switch self {
        case .apple: nil
        case .openRouter: "https://openrouter.ai/api/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .openCode: nil
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: ""
        case .openRouter: "openai/gpt-4o-mini"
        case .groq: "openai/gpt-oss-20b"
        case .openCode: ""
        }
    }

    /// Models the user can pick with one click in Settings. First is the default.
    var suggestedModels: [String] {
        switch self {
        case .apple, .openCode: []
        case .openRouter: ["openai/gpt-4o-mini", "openai/gpt-oss-20b"]
        case .groq: ["openai/gpt-oss-20b", "openai/gpt-oss-120b"]
        }
    }

    /// IDs that no longer resolve on the provider (retired or moved to
    /// Enterprise). Stored prefs with these values fall back to `defaultModel`.
    var retiredModels: [String] {
        switch self {
        case .groq: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]
        case .apple, .openRouter, .openCode: []
        }
    }

    /// Extra headers per gateway (OpenRouter attribution; harmless elsewhere
    /// so only set for OpenRouter).
    var extraHeaders: [String: String] {
        switch self {
        case .openRouter: ["X-Title": "OpenWhisper"]
        case .apple, .groq, .openCode: [:]
        }
    }
}

/// Credentials for one remote gateway. Empty baseURL falls back to the
/// provider preset; empty model falls back too (except OpenCode, whose
/// default is empty → unavailable until filled).
struct GatewayConfig: Equatable, Sendable {
    var baseURL: String
    var apiKey: String
    var model: String
}

/// Nonisolated UserDefaults access. The polish loop runs off the main actor,
/// so the routing polisher cannot touch `@MainActor AppSettings` — all
/// reads here are plain `UserDefaults.standard` (thread-safe).
enum GatewayStore {
    private static var defaults: UserDefaults { UserDefaults.standard }

    static func provider() -> AIProvider {
        guard let raw = defaults.string(forKey: "aiProvider"),
              let provider = AIProvider(rawValue: raw) else {
            return .apple
        }
        return provider
    }

    static func setProvider(_ provider: AIProvider) {
        defaults.set(provider.rawValue, forKey: "aiProvider")
    }

    static func config(for provider: AIProvider) -> GatewayConfig {
        let prefix = provider.rawValue
        let storedBase = defaults.string(forKey: "gatewayBaseURL_\(prefix)") ?? ""
        var storedModel = defaults.string(forKey: "gatewayModel_\(prefix)") ?? ""
        if provider.retiredModels.contains(storedModel) {
            storedModel = ""
        }
        return GatewayConfig(
            baseURL: storedBase.isEmpty ? (provider.defaultBaseURL ?? "") : storedBase,
            apiKey: defaults.string(forKey: "gatewayKey_\(prefix)") ?? "",
            model: storedModel.isEmpty ? provider.defaultModel : storedModel
        )
    }

    static func setBaseURL(_ value: String, for provider: AIProvider) {
        defaults.set(value, forKey: "gatewayBaseURL_\(provider.rawValue)")
    }

    static func setKey(_ value: String, for provider: AIProvider) {
        defaults.set(value, forKey: "gatewayKey_\(provider.rawValue)")
    }

    static func setModel(_ value: String, for provider: AIProvider) {
        defaults.set(value, forKey: "gatewayModel_\(provider.rawValue)")
    }
}
