import AppKit
import Foundation

struct FnHotkeyEvent {
    let isFnPressed: Bool
    let timestamp: TimeInterval
}

final class GlobalHotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onFnEvent: ((FnHotkeyEvent) -> Void)?

    deinit {
        stop()
    }

    func start(onFnEvent: @escaping (FnHotkeyEvent) -> Void) {
        stop()
        self.onFnEvent = onFnEvent

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onFnEvent = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == 63 else {
            return
        }

        let deviceIndependentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let nonFunctionFlags = deviceIndependentFlags.subtracting(.function)
        guard nonFunctionFlags.isEmpty else {
            return
        }

        onFnEvent?(
            FnHotkeyEvent(
                isFnPressed: deviceIndependentFlags.contains(.function),
                timestamp: event.timestamp
            )
        )
    }
}
