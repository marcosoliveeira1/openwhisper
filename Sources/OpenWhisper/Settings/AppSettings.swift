import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
enum AppSettings {
    static let defaultHotKeyCode = UInt32(kVK_ANSI_G)
    static let defaultHotKeyModifiers = UInt32(cmdKey | shiftKey)

    private static let defaults = UserDefaults.standard

    static var historyLimit: Int {
        get { defaults.object(forKey: "historyLimit") as? Int ?? TranscriptionStore.defaultCapacity }
        set { defaults.set(newValue, forKey: "historyLimit") }
    }

    static var hotKeyCode: UInt32 {
        get { UInt32(defaults.object(forKey: "hotKeyCode") as? Int ?? Int(defaultHotKeyCode)) }
        set { defaults.set(Int(newValue), forKey: "hotKeyCode") }
    }

    static var hotKeyModifiers: UInt32 {
        get { UInt32(defaults.object(forKey: "hotKeyModifiers") as? Int ?? Int(defaultHotKeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: "hotKeyModifiers") }
    }

    static var autoPasteEnabled: Bool {
        get { defaults.object(forKey: "autoPasteEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoPasteEnabled") }
    }

    static var livePolishEnabled: Bool {
        get { defaults.object(forKey: "livePolishEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "livePolishEnabled") }
    }

    /// Window-timer interval for live correction (seconds). Clamped 5–30.
    static var livePolishWindowSeconds: Int {
        get {
            let raw = defaults.object(forKey: "livePolishWindowSeconds") as? Int ?? 10
            return min(30, max(5, raw))
        }
        set { defaults.set(min(30, max(5, newValue)), forKey: "livePolishWindowSeconds") }
    }

    // MARK: - AI gateway (stored via GatewayStore; plain UserDefaults so the
    // off-main polish loop can read the selection without @MainActor).

    static var aiProviderRaw: String {
        get { GatewayStore.provider().rawValue }
        set {
            if let provider = AIProvider(rawValue: newValue) {
                GatewayStore.setProvider(provider)
            }
        }
    }

    static func gatewayBaseURL(for provider: AIProvider) -> String {
        GatewayStore.config(for: provider).baseURL
    }

    static func gatewayKey(for provider: AIProvider) -> String {
        GatewayStore.config(for: provider).apiKey
    }

    static func gatewayModel(for provider: AIProvider) -> String {
        GatewayStore.config(for: provider).model
    }

    static func setGatewayBaseURL(_ value: String, for provider: AIProvider) {
        GatewayStore.setBaseURL(value, for: provider)
    }

    static func setGatewayKey(_ value: String, for provider: AIProvider) {
        GatewayStore.setKey(value, for: provider)
    }

    static func setGatewayModel(_ value: String, for provider: AIProvider) {
        GatewayStore.setModel(value, for: provider)
    }

    static var appearance: String {
        get { defaults.string(forKey: "appearance") ?? "system" }
        set { defaults.set(newValue, forKey: "appearance") }
    }

    static var panelOpacity: Double {
        get { defaults.object(forKey: "panelOpacity") as? Double ?? 0.85 }
        set { defaults.set(newValue, forKey: "panelOpacity") }
    }
}

enum AppearanceMode {
    static func nsAppearance(_ raw: String) -> NSAppearance? {
        switch raw {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}
