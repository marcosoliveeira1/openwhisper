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
}
