import AppKit
import ApplicationServices
import Foundation

enum TextInjectionError: LocalizedError, Equatable {
    case emptyText
    case accessibilityPermissionRequired
    case focusedElementUnavailable
    case focusedElementNotEditable
    case focusStabilizationTimedOut
    case eventSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "No transcript text is available to inject."
        case .accessibilityPermissionRequired:
            return "Text injection requires Accessibility permission."
        case .focusedElementUnavailable:
            return "No focused target is available for text injection."
        case .focusedElementNotEditable:
            return "The focused target is not editable."
        case .focusStabilizationTimedOut:
            return "Timed out while waiting for a focused editable target."
        case .eventSourceUnavailable:
            return "Unable to generate keyboard events for injection."
        }
    }
}

enum TextInjectionOutcome: Equatable {
    case success
    case successWithWarning(String)
}

struct PasteboardItemSnapshot: Equatable {
    let dataByType: [String: Data]
}

struct PasteboardSnapshot: Equatable {
    let items: [PasteboardItemSnapshot]

    static let empty = PasteboardSnapshot(items: [])
}

protocol PasteboardAccessing {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    @discardableResult func setString(_ string: String) -> Bool
    @discardableResult func restore(_ snapshot: PasteboardSnapshot) -> Bool
}

final class SystemPasteboard: PasteboardAccessing {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func snapshot() -> PasteboardSnapshot {
        let snapshots = (pasteboard.pasteboardItems ?? []).map { item in
            let pairs: [(String, Data)] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type.rawValue, data)
            }
            let dataByType = Dictionary<String, Data>(uniqueKeysWithValues: pairs)
            return PasteboardItemSnapshot(dataByType: dataByType)
        }

        return PasteboardSnapshot(items: snapshots)
    }

    func setString(_ string: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }

    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        pasteboard.clearContents()

        guard !snapshot.items.isEmpty else {
            return true
        }

        let items = snapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()
            for (typeRaw, data) in snapshotItem.dataByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            return item
        }

        return pasteboard.writeObjects(items)
    }
}

@MainActor
final class TextInjectionService: TextInjecting {
    private let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField"
    ]

    private let pasteboard: PasteboardAccessing
    private let sleepNanos: (UInt64) async -> Void

    init(
        pasteboard: PasteboardAccessing = SystemPasteboard(),
        sleepNanos: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.pasteboard = pasteboard
        self.sleepNanos = sleepNanos
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func isEditableRole(_ role: String) -> Bool {
        editableRoles.contains(role)
    }

    func inject(text: String, preferredApplication: NSRunningApplication?) async -> Result<TextInjectionOutcome, TextInjectionError> {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .failure(.emptyText)
        }

        guard isAccessibilityTrusted() else {
            return .failure(.accessibilityPermissionRequired)
        }

        if let preferredApplication {
            _ = preferredApplication.activate(options: [])
            await sleepNanos(120_000_000)
        }

        let fallbackWarning: String?
        if let focusedElement = await waitForFocusedElement() {
            if isEditable(focusedElement: focusedElement) {
                fallbackWarning = nil
            } else {
                fallbackWarning = "Focused target is not exposed as editable; used best-effort paste."
            }
        } else {
            fallbackWarning = "No focused editable target detected; used best-effort paste."
        }

        let backup = pasteboard.snapshot()
        guard pasteboard.setString(trimmedText) else {
            return .failure(.eventSourceUnavailable)
        }
        let injectedChangeCount = pasteboard.changeCount

        guard postCommandV() else {
            return .failure(.eventSourceUnavailable)
        }

        await sleepNanos(70_000_000)

        let restoreOutcome = restoreClipboardAfterInjection(snapshot: backup, injectedChangeCount: injectedChangeCount)
        return .success(mergeOutcome(restoreOutcome, fallbackWarning: fallbackWarning))
    }

    func restoreClipboardAfterInjection(snapshot: PasteboardSnapshot, injectedChangeCount: Int) -> TextInjectionOutcome {
        if pasteboard.changeCount != injectedChangeCount {
            return .successWithWarning("Clipboard changed during injection; restore skipped.")
        }

        if pasteboard.restore(snapshot) {
            return .success
        }

        return .successWithWarning("Transcript injected, but clipboard could not be restored.")
    }

    private func waitForFocusedElement(timeout: TimeInterval = 0.45) async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() <= deadline {
            if let focusedElement = focusedUIElement() {
                return focusedElement
            }
            await sleepNanos(50_000_000)
        }

        return nil
    }

    private func mergeOutcome(_ outcome: TextInjectionOutcome, fallbackWarning: String?) -> TextInjectionOutcome {
        guard let fallbackWarning else {
            return outcome
        }

        switch outcome {
        case .success:
            return .successWithWarning(fallbackWarning)
        case let .successWithWarning(existing):
            return .successWithWarning("\(existing) \(fallbackWarning)")
        }
    }

    private func focusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard result == .success, let focusedValue else {
            return nil
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private func isEditable(focusedElement: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &settable
        )

        if settableResult == .success, settable.boolValue {
            return true
        }

        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )

        guard roleResult == .success, let role = roleValue as? String else {
            return false
        }

        return isEditableRole(role)
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let keyCodeV: CGKeyCode = 9

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
