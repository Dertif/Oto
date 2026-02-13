import Foundation

enum HotkeyIntent: Equatable {
    case start
    case stop
    case toggle
}

final class FnHotkeyInterpreter {
    private let doubleTapWindow: TimeInterval
    private var lastFnDownAt: TimeInterval?
    private var lastFnPressed: Bool?

    init(doubleTapWindow: TimeInterval = 0.32) {
        self.doubleTapWindow = doubleTapWindow
    }

    func reset(for mode: HotkeyTriggerMode) {
        _ = mode
        lastFnDownAt = nil
        lastFnPressed = nil
    }

    func interpret(
        isFnPressed: Bool,
        mode: HotkeyTriggerMode,
        timestamp: TimeInterval,
        isProcessing: Bool
    ) -> HotkeyIntent? {
        if lastFnPressed == isFnPressed {
            return nil
        }
        lastFnPressed = isFnPressed

        guard !isProcessing else {
            return nil
        }

        switch mode {
        case .hold:
            return isFnPressed ? .start : .stop

        case .doubleTap:
            guard isFnPressed else {
                return nil
            }
            if let lastFnDownAt, (timestamp - lastFnDownAt) <= doubleTapWindow {
                self.lastFnDownAt = nil
                return .toggle
            }
            lastFnDownAt = timestamp
            return nil
        }
    }
}
