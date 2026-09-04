import Carbon.HIToolbox
import Cocoa
import SwiftUI

struct HotKeyRecorderField: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onChange: () -> Void

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.updateDisplay(keyCode: keyCode, modifiers: modifiers)
        button.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
            onChange()
        }
        return button
    }

    func updateNSView(_ nsView: HotKeyRecorderButton, context: Context) {
        nsView.updateDisplay(keyCode: keyCode, modifiers: modifiers)
    }
}

final class HotKeyRecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?
    private var monitor: Any?
    private var currentKeyCode: UInt32 = AppSettings.defaultHotKeyCode
    private var currentModifiers: UInt32 = AppSettings.defaultHotKeyModifiers

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
        bezelStyle = .rounded
        target = self
        action = #selector(clicked)
        setButtonType(.momentaryPushIn)
        updateDisplay(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func updateDisplay(keyCode: UInt32, modifiers: UInt32) {
        guard monitor == nil else { return }
        currentKeyCode = keyCode
        currentModifiers = modifiers
        title = Self.comboString(keyCode: keyCode, modifiers: modifiers)
    }

    @objc private func clicked() {
        if monitor != nil {
            stopRecording()
            return
        }
        title = "Pressione atalho…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if keyCode == UInt32(kVK_Escape) {
            stopRecording()
            return
        }
        guard !Self.isModifierKeyCode(keyCode) else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        guard carbonMods != 0 else { return }
        currentKeyCode = keyCode
        currentModifiers = carbonMods
        stopRecording()
        onCapture?(keyCode, carbonMods)
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        title = Self.comboString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    private static func isModifierKeyCode(_ code: UInt32) -> Bool {
        [UInt32(kVK_Shift), UInt32(kVK_RightShift), UInt32(kVK_Command), UInt32(kVK_RightCommand),
         UInt32(kVK_Option), UInt32(kVK_RightOption), UInt32(kVK_Control), UInt32(kVK_RightControl),
         UInt32(kVK_Function), UInt32(kVK_CapsLock)].contains(code)
    }

    static func comboString(keyCode: UInt32, modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        return symbols + keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        let letters: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 36: "L", 37: "J", 40: "K", 45: "M", 38: "N"
        ]
        let symbols: [UInt32: String] = [
            50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\"
        ]
        let digits: [UInt32: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0"
        ]
        let specials: [UInt32: String] = [
            49: "Space", 51: "Delete", 53: "Esc", 48: "Tab",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End",
            116: "Page Up", 121: "Page Down"
        ]
        if let letter = letters[code] { return letter }
        if let digit = digits[code] { return digit }
        if let symbol = symbols[code] { return symbol }
        if let special = specials[code] { return special }
        return "Tecla \(code)"
    }
}
