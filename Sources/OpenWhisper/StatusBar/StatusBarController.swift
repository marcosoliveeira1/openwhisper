import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let store: TranscriptionStore
    private let statusItem: NSStatusItem
    private var cachedEntries: [Transcription] = []
    private var cancellables: Set<AnyCancellable> = []
    private let openSettings: () -> Void

    init(model: AppModel, store: TranscriptionStore, openSettings: @escaping () -> Void) {
        self.model = model
        self.store = store
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "OpenWhisper")
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        model.$historyVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCache()
            }
            .store(in: &cancellables)

        refreshCache()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = HistoryMenuBuilder.build(entries: cachedEntries)
        populate(menu: menu, with: items)
    }

    private func refreshCache() {
        Task {
            cachedEntries = await store.all()
        }
    }

    private func populate(menu: NSMenu, with items: [MenuModel.Item]) {
        for item in items {
            if item.kind == .settings || item.kind == .quit {
                menu.addItem(.separator())
            }
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            switch item.kind {
            case .transcription(let text):
                menuItem.target = self
                menuItem.action = #selector(transcriptionClicked(_:))
                menuItem.representedObject = text
                menuItem.toolTip = text
            case .empty:
                break
            case .clear:
                menuItem.target = self
                menuItem.action = #selector(clearClicked(_:))
            case .settings:
                menuItem.target = self
                menuItem.action = #selector(settingsClicked(_:))
                menuItem.keyEquivalent = ","
                menuItem.keyEquivalentModifierMask = .command
            case .about:
                menuItem.target = self
                menuItem.action = #selector(aboutClicked(_:))
            case .quit:
                menuItem.action = #selector(NSApplication.terminate(_:))
            }
            menuItem.isEnabled = item.isEnabled
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

    @objc private func settingsClicked(_ sender: NSMenuItem) {
        openSettings()
    }

    @objc private func aboutClicked(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
