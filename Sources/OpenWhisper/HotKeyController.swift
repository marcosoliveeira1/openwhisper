import Carbon.HIToolbox
import Foundation

final class HotKeyController: @unchecked Sendable {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func start() {
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    controller.handler()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F57_4853), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        hotKeyRef = nil
    }
}
