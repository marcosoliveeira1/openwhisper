import AppKit
import ApplicationServices

protocol AutoPasteService: AnyObject, Sendable {
    @MainActor
    func paste(into pid: pid_t?) async
}

@MainActor
enum FocusRestorer {
    static func activate(pid: pid_t?) {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
        // Tira o painel flutuante da frente antes de devolver o foco,
        // senão o ⌘V pode cair no próprio OpenWhisper.
        // `if let` porque nos testes não há NSApp (nil) — acesso direto crasha.
        if let shared = NSApp {
            shared.hide(nil)
        }
        // activateIgnoringOtherApps é necessário porque o painel estava key.
        _ = app.activate(options: .activateIgnoringOtherApps)
    }
}

final class CGEventAutoPasteService: AutoPasteService, @unchecked Sendable {
    /// Quanto tempo espera o app de destino assumir o foco antes do ⌘V.
    /// 180ms era curto em máquinas lentas — o paste caía no app errado.
    private static let focusDelay: Duration = .milliseconds(350)

    func paste(into pid: pid_t?) async {
        guard Self.isTrusted() else {
            NSLog("[OpenWhisper] AutoPaste bloqueado: sem permissão de Acessibilidade. Abortando este paste e pedindo grant.")
            Self.promptPermission()
            return
        }
        // O deliver() já colocou o painel em .idle (orderOut); esconde o app
        // e devolve o foco antes de sintetizar o ⌘V.
        // paste já roda no @MainActor (protocolo), então chama direto.
        FocusRestorer.activate(pid: pid)
        try? await Task.sleep(for: Self.focusDelay)
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
        // Com prompt:true o macOS mostra o diálogo "gostaria de controlar"
        // com botão para abrir os Ajustes.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Abre direto a página de Acessibilidade (macOS 13+ usa o deep link
    /// comPrivacy_Accessibility; o scheme antigo parou de focar a seção).
    static func openAccessibilitySettings() {
        promptPermission()
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                break
            }
        }
    }
}
