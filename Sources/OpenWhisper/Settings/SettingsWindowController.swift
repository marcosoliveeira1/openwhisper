import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @State private var hotKeyCode: UInt32
    @State private var hotKeyModifiers: UInt32
    @State private var limitText: String
    @State private var lastValidLimit: Int
    @State private var autoPasteEnabled: Bool
    @State private var accessibilityTrusted: Bool
    @State private var appearance: String

    var onHotKeyChanged: (UInt32, UInt32) -> Void
    var onLimitChanged: (Int) -> Void
    var onClearHistory: () -> Void
    var onAutoPasteChanged: (Bool) -> Void
    var onAppearanceChanged: (String) -> Void

    init(
        hotKeyCode: UInt32,
        hotKeyModifiers: UInt32,
        historyLimit: Int,
        autoPasteEnabled: Bool,
        appearance: String,
        onHotKeyChanged: @escaping (UInt32, UInt32) -> Void,
        onLimitChanged: @escaping (Int) -> Void,
        onClearHistory: @escaping () -> Void,
        onAutoPasteChanged: @escaping (Bool) -> Void,
        onAppearanceChanged: @escaping (String) -> Void
    ) {
        _hotKeyCode = State(initialValue: hotKeyCode)
        _hotKeyModifiers = State(initialValue: hotKeyModifiers)
        _limitText = State(initialValue: String(historyLimit))
        _lastValidLimit = State(initialValue: historyLimit)
        _autoPasteEnabled = State(initialValue: autoPasteEnabled)
        _accessibilityTrusted = State(initialValue: CGEventAutoPasteService.isTrusted())
        _appearance = State(initialValue: appearance)
        self.onHotKeyChanged = onHotKeyChanged
        self.onLimitChanged = onLimitChanged
        self.onClearHistory = onClearHistory
        self.onAutoPasteChanged = onAutoPasteChanged
        self.onAppearanceChanged = onAppearanceChanged
    }

    var body: some View {
        Form {
            Section("Atalho global") {
                LabeledContent("Ativar ditado") {
                    HotKeyRecorderField(
                        keyCode: $hotKeyCode,
                        modifiers: $hotKeyModifiers,
                        onChange: {
                            onHotKeyChanged(hotKeyCode, hotKeyModifiers)
                        }
                    )
                    .frame(width: 150)
                }
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Clique no atalho e pressione a nova combinação. Esc cancela.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Aparência") {
                LabeledContent("Tema") {
                    Picker("", selection: $appearance) {
                        Text("Sistema").tag("system")
                        Text("Claro").tag("light")
                        Text("Escuro").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .onChange(of: appearance) { _, newValue in
                        onAppearanceChanged(newValue)
                    }
                }
            }
            Section("Colagem") {
                LabeledContent("Após ditar") {
                    Toggle("Colar automaticamente", isOn: $autoPasteEnabled)
                        .onChange(of: autoPasteEnabled) { _, newValue in
                            onAutoPasteChanged(newValue)
                        }
                }
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Cola o texto no app que estava em foco ao iniciar o ditado. Requer permissão de Acessibilidade.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !accessibilityTrusted {
                    LabeledContent {
                        Button("Abrir Ajustes de Acessibilidade") {
                            CGEventAutoPasteService.promptPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        Text("Permissão pendente")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("Histórico") {
                LabeledContent("Manter transcrições") {
                    HStack(spacing: 8) {
                        TextField("50", text: $limitText)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 56)
                            .onSubmit(applyLimit)
                        Stepper("", onIncrement: { bumpLimit(5) }, onDecrement: { bumpLimit(-5) })
                            .labelsHidden()
                            .fixedSize()
                    }
                }
                LabeledContent {
                    Button("Limpar histórico", role: .destructive) {
                        onClearHistory()
                    }
                } label: {
                    Text("Dados")
                }
            }
            Section("Sobre") {
                LabeledContent("Versão") {
                    Text(versionString).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = CGEventAutoPasteService.isTrusted()
        }
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "OpenWhisper \(short ?? "0.1")"
    }

    private func applyLimit() {
        guard let value = Int(limitText.trimmingCharacters(in: .whitespaces)) else {
            limitText = String(lastValidLimit)
            return
        }
        let clamped = min(500, max(1, value))
        limitText = String(clamped)
        lastValidLimit = clamped
        onLimitChanged(clamped)
    }

    private func bumpLimit(_ delta: Int) {
        let clamped = min(500, max(1, lastValidLimit + delta))
        limitText = String(clamped)
        lastValidLimit = clamped
        onLimitChanged(clamped)
    }
}

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let hotKey: HotKeyController
    private let store: TranscriptionStore
    private let window: NSWindow

    init(model: AppModel, hotKey: HotKeyController, store: TranscriptionStore) {
        self.model = model
        self.hotKey = hotKey
        self.store = store

        let view = SettingsView(
            hotKeyCode: AppSettings.hotKeyCode,
            hotKeyModifiers: AppSettings.hotKeyModifiers,
            historyLimit: AppSettings.historyLimit,
            autoPasteEnabled: AppSettings.autoPasteEnabled,
            appearance: AppSettings.appearance,
            onHotKeyChanged: { code, modifiers in
                hotKey.update(keyCode: code, modifiers: modifiers)
                AppSettings.hotKeyCode = code
                AppSettings.hotKeyModifiers = modifiers
            },
            onLimitChanged: { limit in
                AppSettings.historyLimit = limit
                Task {
                    await store.setCapacity(limit)
                }
            },
            onClearHistory: {
                model.clearHistory()
            },
            onAutoPasteChanged: { enabled in
                AppSettings.autoPasteEnabled = enabled
            },
            onAppearanceChanged: { mode in
                AppSettings.appearance = mode
                NSApp.appearance = AppearanceMode.nsAppearance(mode)
            }
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configurações"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
