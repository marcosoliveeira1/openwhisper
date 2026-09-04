import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var panelController: DictationPanelController?
    private var statusBar: StatusBarController?
    private var hotKey: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWhisper", isDirectory: true)
            .appendingPathComponent("history.json")
        let store = TranscriptionStore(fileURL: storeURL, capacity: AppSettings.historyLimit)
        let model = AppModel(
            dictation: AppleSpeechService(),
            clipboard: NSPasteboardClipboard(),
            store: store,
            autoPaste: CGEventAutoPasteService(),
            isAutoPasteEnabled: { AppSettings.autoPasteEnabled }
        )
        self.model = model
        panelController = DictationPanelController(model: model)
        let hotKey = HotKeyController(
            keyCode: AppSettings.hotKeyCode,
            modifiers: AppSettings.hotKeyModifiers
        ) {
            model.toggle()
        }
        self.hotKey = hotKey
        hotKey.start()
        let settingsWindow = SettingsWindowController(model: model, hotKey: hotKey, store: store)
        statusBar = StatusBarController(model: model, store: store) {
            settingsWindow.show()
        }
    }
}
