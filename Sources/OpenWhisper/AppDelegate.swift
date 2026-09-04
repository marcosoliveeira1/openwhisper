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
        let store = TranscriptionStore(fileURL: storeURL)
        let model = AppModel(
            dictation: AppleSpeechService(),
            clipboard: NSPasteboardClipboard(),
            store: store
        )
        self.model = model
        panelController = DictationPanelController(model: model)
        statusBar = StatusBarController(model: model, store: store)
        hotKey = HotKeyController(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey)) {
            model.toggle()
        }
        hotKey?.start()
    }
}
