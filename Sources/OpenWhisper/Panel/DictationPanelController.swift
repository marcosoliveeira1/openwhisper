import AppKit
import Combine
import SwiftUI

final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class DictationPanelController {
    private let model: AppModel
    private let panel: DictationPanel
    private var escMonitor: Any?
    private var cancellable: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        panel = DictationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = true

        let hostingView = NSHostingView(rootView: DictationView(model: model))
        panel.contentView = hostingView

        cancellable = model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .idle {
                    self?.dismiss()
                } else {
                    self?.present()
                }
            }
    }

    private func present() {
        if !panel.isVisible {
            positionAtTopCenter()
            panel.orderFront(nil)
        }
        installEscMonitor()
    }

    private func dismiss() {
        panel.orderOut(nil)
        removeEscMonitor()
    }

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.model.cancel()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
        }
        escMonitor = nil
    }
}
