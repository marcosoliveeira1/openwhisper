import AppKit
import ApplicationServices

protocol AutoPasteService: AnyObject, Sendable {
    @MainActor
    func paste(into pid: pid_t?) async
}

enum FocusRestorer {
    static func activate(pid: pid_t?) {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }
}

final class CGEventAutoPasteService: AutoPasteService, @unchecked Sendable {
    func paste(into pid: pid_t?) async {
        guard Self.isTrusted() else {
            Self.promptPermission()
            return
        }
        FocusRestorer.activate(pid: pid)
        try? await Task.sleep(for: .milliseconds(180))
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(9)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptPermission() {
        let key = "AXTrustedCheckOptionPrompt"
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
