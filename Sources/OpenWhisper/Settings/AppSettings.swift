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
