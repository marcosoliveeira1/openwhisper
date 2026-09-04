import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let store: TranscriptionStore
    private let statusItem: NSStatusItem

    init(model: AppModel, store: TranscriptionStore) {
        self.model = model
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "OpenWhisper")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        Task {
            let entries = await store.all()
            let items = HistoryMenuBuilder.build(entries: entries)
            populate(menu: menu, with: items)
        }
    }

    private func populate(menu: NSMenu, with items: [MenuModel.Item]) {
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            switch item.kind {
            case .transcription(let text):
                menuItem.target = self
                menuItem.action = #selector(transcriptionClicked(_:))
                menuItem.representedObject = text
                menuItem.toolTip = text
            case .empty:
                menuItem.isEnabled = false
            case .clear:
                menuItem.target = self
                menuItem.action = #selector(clearClicked(_:))
                menuItem.isEnabled = !items.contains { if case .transcription = $0.kind { return true }; return false }
            case .quit:
                menuItem.action = #selector(NSApplication.terminate(_:))
            }
            menu.addItem(menuItem)
        }
    }

    @objc private func transcriptionClicked(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        model.copyToClipboard(text)
    }

    @objc private func clearClicked(_ sender: NSMenuItem) {
        model.clearHistory()
    }
}
