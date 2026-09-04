import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Atalho global") {
                Text("⌘⇧G").font(.system(.body, design: .monospaced))
            }
            LabeledContent("Idioma") {
                Text("Português (Brasil)")
            }
            LabeledContent("Histórico") {
                Text("Últimas 50 transcrições")
            }
            LabeledContent("Versão") {
                Text(version)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 340)
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short.map { "OpenWhisper \($0)" } ?? "OpenWhisper"
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let window: NSWindow

    private init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configurações"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
