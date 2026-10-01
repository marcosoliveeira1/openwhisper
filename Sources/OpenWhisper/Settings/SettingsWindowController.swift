import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @State private var hotKeyCode: UInt32
    @State private var hotKeyModifiers: UInt32
    @State private var limitText: String
    @State private var lastValidLimit: Int
    @State private var autoPasteEnabled: Bool
    @State private var livePolishEnabled: Bool
    @State private var aiProviderRaw: String
    @State private var gatewayBaseURL: String
    @State private var gatewayKey: String
    @State private var gatewayModel: String
    @State private var accessibilityTrusted: Bool
    @State private var appearance: String
    @State private var panelOpacity: Double

    var onHotKeyChanged: (UInt32, UInt32) -> Void
    var onLimitChanged: (Int) -> Void
    var onClearHistory: () -> Void
    var onAutoPasteChanged: (Bool) -> Void
    var onLivePolishChanged: (Bool) -> Void
    var onAppearanceChanged: (String) -> Void
    var onPanelOpacityChanged: (Double) -> Void

    init(
        hotKeyCode: UInt32,
        hotKeyModifiers: UInt32,
        historyLimit: Int,
        autoPasteEnabled: Bool,
        livePolishEnabled: Bool,
        aiProviderRaw: String,
        appearance: String,
        panelOpacity: Double,
        onHotKeyChanged: @escaping (UInt32, UInt32) -> Void,
        onLimitChanged: @escaping (Int) -> Void,
        onClearHistory: @escaping () -> Void,
        onAutoPasteChanged: @escaping (Bool) -> Void,
        onLivePolishChanged: @escaping (Bool) -> Void,
        onAppearanceChanged: @escaping (String) -> Void,
        onPanelOpacityChanged: @escaping (Double) -> Void
    ) {
        _hotKeyCode = State(initialValue: hotKeyCode)
        _hotKeyModifiers = State(initialValue: hotKeyModifiers)
        _limitText = State(initialValue: String(historyLimit))
        _lastValidLimit = State(initialValue: historyLimit)
        _autoPasteEnabled = State(initialValue: autoPasteEnabled)
        _livePolishEnabled = State(initialValue: livePolishEnabled)
        _aiProviderRaw = State(initialValue: aiProviderRaw)
        let initialProvider = AIProvider(rawValue: aiProviderRaw) ?? .apple
        _gatewayBaseURL = State(initialValue: AppSettings.gatewayBaseURL(for: initialProvider))
        _gatewayKey = State(initialValue: AppSettings.gatewayKey(for: initialProvider))
        _gatewayModel = State(initialValue: AppSettings.gatewayModel(for: initialProvider))
        _accessibilityTrusted = State(initialValue: CGEventAutoPasteService.isTrusted())
        _appearance = State(initialValue: appearance)
        _panelOpacity = State(initialValue: panelOpacity)
        self.onHotKeyChanged = onHotKeyChanged
        self.onLimitChanged = onLimitChanged
        self.onClearHistory = onClearHistory
        self.onAutoPasteChanged = onAutoPasteChanged
        self.onLivePolishChanged = onLivePolishChanged
        self.onAppearanceChanged = onAppearanceChanged
        self.onPanelOpacityChanged = onPanelOpacityChanged
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
                LabeledContent("Transparência do painel") {
                    Picker("", selection: $panelOpacity) {
                        Text("Sólido").tag(1.0)
                        Text("85%").tag(0.85)
                        Text("70%").tag(0.7)
                        Text("55%").tag(0.55)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .onChange(of: panelOpacity) { _, newValue in
                        onPanelOpacityChanged(newValue)
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
            Section("IA") {
                LabeledContent("Provedor") {
                    Picker("", selection: $aiProviderRaw) {
                        ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .onChange(of: aiProviderRaw) { _, newValue in
                        AppSettings.aiProviderRaw = newValue
                        loadGatewayFields()
                    }
                }
                if let provider = AIProvider(rawValue: aiProviderRaw), !provider.isLocal {
                    LabeledContent("URL base") {
                        TextField(provider.defaultBaseURL ?? "https://…", text: $gatewayBaseURL)
                            .frame(width: 240)
                            .onChange(of: gatewayBaseURL) { _, _ in
                                saveGatewayFields()
                            }
                    }
                    LabeledContent("Chave API") {
                        SecureField("Bearer token", text: $gatewayKey)
                            .frame(width: 240)
                            .onChange(of: gatewayKey) { _, _ in
                                saveGatewayFields()
                            }
                    }
                    LabeledContent("Modelo") {
                        TextField(provider.defaultModel.isEmpty ? "model-id" : provider.defaultModel, text: $gatewayModel)
                            .frame(width: 240)
                            .onChange(of: gatewayModel) { _, _ in
                                saveGatewayFields()
                            }
                    }
                    LabeledContent {
                        EmptyView()
                    } label: {
                        Text(gatewayHint(for: provider))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Durante a fala") {
                    Toggle("Limpeza ao vivo", isOn: $livePolishEnabled)
                        .onChange(of: livePolishEnabled) { _, newValue in
                            onLivePolishChanged(newValue)
                        }
                }
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Mostra o texto corrigido abaixo do original enquanto você fala. Só frases fechadas vão para a IA, uma por vez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .apple
    }

    private func loadGatewayFields() {
        gatewayBaseURL = AppSettings.gatewayBaseURL(for: selectedProvider)
        gatewayKey = AppSettings.gatewayKey(for: selectedProvider)
        gatewayModel = AppSettings.gatewayModel(for: selectedProvider)
    }

    private func saveGatewayFields() {
        AppSettings.setGatewayBaseURL(gatewayBaseURL, for: selectedProvider)
        AppSettings.setGatewayKey(gatewayKey, for: selectedProvider)
        AppSettings.setGatewayModel(gatewayModel, for: selectedProvider)
    }

    private func gatewayHint(for provider: AIProvider) -> String {
        switch provider {
        case .apple:
            return ""
        case .openRouter:
            return "Compatível com /chat/completions. A chave fica salva neste Mac."
        case .groq:
            return "Compatível com /chat/completions. A chave fica salva neste Mac."
        case .openCode:
            return "Gateway OpenAI-compatível: informe base URL, bearer e modelo."
        }
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
            livePolishEnabled: AppSettings.livePolishEnabled,
            aiProviderRaw: AppSettings.aiProviderRaw,
            appearance: AppSettings.appearance,
            panelOpacity: AppSettings.panelOpacity,
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
            onLivePolishChanged: { enabled in
                AppSettings.livePolishEnabled = enabled
            },
            onAppearanceChanged: { mode in
                AppSettings.appearance = mode
                NSApp.appearance = AppearanceMode.nsAppearance(mode)
            },
            onPanelOpacityChanged: { opacity in
                AppSettings.panelOpacity = opacity
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
