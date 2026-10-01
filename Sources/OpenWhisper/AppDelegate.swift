import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var panelController: DictationPanelController?
    private var statusBar: StatusBarController?
    private var hotKey: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = AppearanceMode.nsAppearance(AppSettings.appearance)
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWhisper", isDirectory: true)
            .appendingPathComponent("history.json")
        let store = TranscriptionStore(fileURL: storeURL, capacity: AppSettings.historyLimit)
        let applePolisher: (any TextPolisher)? = {
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return FoundationModelsPolisher()
            }
            #endif
            return nil
        }()
        // Routing polisher reads the Settings-selected backend at call time,
        // so switching provider needs no restart.
        let polisher: any TextPolisher = RoutingPolisher(apple: applePolisher)
        let model = AppModel(
            dictation: AppleSpeechService(),
            clipboard: NSPasteboardClipboard(),
            store: store,
            autoPaste: CGEventAutoPasteService(),
            polisher: polisher,
            isAutoPasteEnabled: { AppSettings.autoPasteEnabled },
            isLivePolishEnabled: { AppSettings.livePolishEnabled }
        )
        self.model = model
        let hotKey = HotKeyController(
            keyCode: AppSettings.hotKeyCode,
            modifiers: AppSettings.hotKeyModifiers
        ) {
            model.toggle()
        }
        self.hotKey = hotKey
        hotKey.start()
        let settingsWindow = SettingsWindowController(model: model, hotKey: hotKey, store: store)
        let statusBar = StatusBarController(model: model, store: store) {
            settingsWindow.show()
        }
        self.statusBar = statusBar
        panelController = DictationPanelController(model: model) { [weak statusBar] in
            statusBar?.popUpMenu()
        }
    }
}
