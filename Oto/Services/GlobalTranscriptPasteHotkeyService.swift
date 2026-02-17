import Carbon
import Foundation

final class GlobalTranscriptPasteHotkeyService {
    private let hotKeySignature: OSType = 0x4F544F56 // OTOV
    private let hotKeyIdentifier: UInt32 = 1
    private let hotKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    private let hotKeyModifiers: UInt32 = UInt32(controlKey) | UInt32(cmdKey)

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var onPressed: (() -> Void)?

    private lazy var eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let userData else {
            return noErr
        }
        let service = Unmanaged<GlobalTranscriptPasteHotkeyService>.fromOpaque(userData).takeUnretainedValue()
        return service.handle(eventRef: eventRef)
    }

    deinit {
        stop()
    }

    func start(onPressed: @escaping () -> Void) {
        stop()
        self.onPressed = onPressed

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            OtoLogger.log("Failed to install global paste hotkey handler (status=\(installStatus))", category: .hotkey, level: .error)
            return
        }

        var hotKeyID = EventHotKeyID(
            signature: hotKeySignature,
            id: hotKeyIdentifier
        )

        let registerStatus = RegisterEventHotKey(
            hotKeyCode,
            hotKeyModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            OtoLogger.log("Registered global transcript paste hotkey Ctrl+Cmd+V", category: .hotkey, level: .info)
        } else {
            OtoLogger.log("Failed to register global transcript paste hotkey (status=\(registerStatus))", category: .hotkey, level: .error)
            stop()
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        onPressed = nil
    }

    private func handle(eventRef: EventRef?) -> OSStatus {
        guard let eventRef else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard
            status == noErr,
            hotKeyID.signature == hotKeySignature,
            hotKeyID.id == hotKeyIdentifier
        else {
            return noErr
        }

        onPressed?()
        return noErr
    }
}
