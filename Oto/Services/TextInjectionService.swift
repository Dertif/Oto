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
            return "Timed out while waiting for a focused target."
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

struct TextInjectionRuntime {
    var focusedElementProvider: () -> AXUIElement?
    var roleProvider: (AXUIElement) -> String?
    var subroleProvider: (AXUIElement) -> String?
    var processIDProvider: (AXUIElement) -> pid_t?
    var activatePreferredApp: (NSRunningApplication) -> Bool
    var frontmostApplicationProvider: () -> NSRunningApplication?
    var isAccessibilityTrusted: () -> Bool
    var requestAccessibilityPermission: () -> Void
    var insertText: (AXUIElement, String) -> AXError
    var setValue: (AXUIElement, String) -> AXError
    var isValueSettable: (AXUIElement) -> Bool
    var postCommandV: () -> Bool

    static let live = TextInjectionRuntime(
        focusedElementProvider: {
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
        },
        roleProvider: { element in
            TextInjectionRuntime.stringAttribute(element: element, attribute: kAXRoleAttribute as String)
        },
        subroleProvider: { element in
            TextInjectionRuntime.stringAttribute(element: element, attribute: kAXSubroleAttribute as String)
        },
        processIDProvider: { element in
            var pid: pid_t = 0
            let result = AXUIElementGetPid(element, &pid)
            return result == .success ? pid : nil
        },
        activatePreferredApp: { app in
            app.activate(options: [])
        },
        frontmostApplicationProvider: {
            NSWorkspace.shared.frontmostApplication
        },
        isAccessibilityTrusted: {
            AXIsProcessTrusted()
        },
        requestAccessibilityPermission: {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        insertText: { element, text in
            AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        },
        setValue: { element, text in
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        },
        isValueSettable: { element in
            var settable = DarwinBoolean(false)
            let result = AXUIElementIsAttributeSettable(
                element,
                kAXValueAttribute as CFString,
                &settable
            )
            return result == .success && settable.boolValue
        },
        postCommandV: {
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
    )

    private static func stringAttribute(element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        guard result == .success, let typedValue = value as? String else {
            return nil
        }
        return typedValue
    }
}

@MainActor
final class TextInjectionService: TextInjecting {
    private struct FocusedElementSnapshot {
        let element: AXUIElement
        let role: String?
        let subrole: String?
        let processID: pid_t?
        let waitMilliseconds: Int
    }

    private struct FocusWaitResult {
        let focusedElement: FocusedElementSnapshot?
        let waitMilliseconds: Int
    }

    private let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField"
    ]

    private let runtime: TextInjectionRuntime
    private let pasteboard: PasteboardAccessing
    private let sleepNanos: (UInt64) async -> Void

    init(
        runtime: TextInjectionRuntime = .live,
        pasteboard: PasteboardAccessing = SystemPasteboard(),
        sleepNanos: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.runtime = runtime
        self.pasteboard = pasteboard
        self.sleepNanos = sleepNanos
    }

    func isAccessibilityTrusted() -> Bool {
        runtime.isAccessibilityTrusted()
    }

    func requestAccessibilityPermission() {
        runtime.requestAccessibilityPermission()
    }

    func isEditableRole(_ role: String) -> Bool {
        editableRoles.contains(role)
    }

    func inject(request: TextInjectionRequest) async -> TextInjectionReport {
        let strategyChain = InjectionStrategy.allCases
        let preferredBundleID = request.preferredApplication?.bundleIdentifier
        var attempts: [InjectionAttempt] = []
        var finalStrategy: InjectionStrategy?

        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .failure(
                .emptyText,
                diagnostics: buildDiagnostics(
                    strategyChain: strategyChain,
                    attempts: attempts,
                    finalStrategy: finalStrategy,
                    focusedElement: nil,
                    focusWaitMilliseconds: 0,
                    preferredAppBundleID: preferredBundleID,
                    preferredAppActivated: false
                )
            )
        }

        guard isAccessibilityTrusted() else {
            return .failure(
                .accessibilityPermissionRequired,
                diagnostics: buildDiagnostics(
                    strategyChain: strategyChain,
                    attempts: attempts,
                    finalStrategy: finalStrategy,
                    focusedElement: nil,
                    focusWaitMilliseconds: 0,
                    preferredAppBundleID: preferredBundleID,
                    preferredAppActivated: false
                )
            )
        }

        let preferredActivated: Bool
        if let preferredApplication = request.preferredApplication {
            preferredActivated = runtime.activatePreferredApp(preferredApplication)
            await sleepNanos(120_000_000)
        } else {
            preferredActivated = false
        }

        let focusResult = await waitForFocusedElement(timeout: 0.9, pollInterval: 0.05)
        let focusedElement = focusResult.focusedElement

        if let focusedElement {
            let insertAttempt = attemptAXInsertText(text: trimmedText, focusedElement: focusedElement)
            attempts.append(insertAttempt)
            OtoLogger.log("Injection attempt \(insertAttempt.strategy.rawValue): \(insertAttempt.result.rawValue)", category: .injection, level: .debug)

            if insertAttempt.result == .success {
                finalStrategy = .axInsertText
                return .success(
                    .success,
                    diagnostics: buildDiagnostics(
                        strategyChain: strategyChain,
                        attempts: attempts,
                        finalStrategy: finalStrategy,
                        focusedElement: focusedElement,
                        focusWaitMilliseconds: focusResult.waitMilliseconds,
                        preferredAppBundleID: preferredBundleID,
                        preferredAppActivated: preferredActivated
                    )
                )
            }

            let setValueAttempt = attemptAXSetValue(text: trimmedText, focusedElement: focusedElement)
            attempts.append(setValueAttempt)
            OtoLogger.log("Injection attempt \(setValueAttempt.strategy.rawValue): \(setValueAttempt.result.rawValue)", category: .injection, level: .debug)

            if setValueAttempt.result == .success {
                finalStrategy = .axSetValue
                return .success(
                    .success,
                    diagnostics: buildDiagnostics(
                        strategyChain: strategyChain,
                        attempts: attempts,
                        finalStrategy: finalStrategy,
                        focusedElement: focusedElement,
                        focusWaitMilliseconds: focusResult.waitMilliseconds,
                        preferredAppBundleID: preferredBundleID,
                        preferredAppActivated: preferredActivated
                    )
                )
            }
        } else {
            attempts.append(InjectionAttempt(
                strategy: .axInsertText,
                result: .skipped,
                reason: "No focused target available."
            ))
            attempts.append(InjectionAttempt(
                strategy: .axSetValue,
                result: .skipped,
                reason: "No focused target available."
            ))
        }

        guard request.allowCommandVFallback else {
            attempts.append(InjectionAttempt(
                strategy: .commandV,
                result: .skipped,
                reason: "Cmd+V fallback disabled by user setting."
            ))

            let error: TextInjectionError = focusedElement == nil ? .focusStabilizationTimedOut : .focusedElementNotEditable
            return .failure(
                error,
                diagnostics: buildDiagnostics(
                    strategyChain: strategyChain,
                    attempts: attempts,
                    finalStrategy: finalStrategy,
                    focusedElement: focusedElement,
                    focusWaitMilliseconds: focusResult.waitMilliseconds,
                    preferredAppBundleID: preferredBundleID,
                    preferredAppActivated: preferredActivated
                )
            )
        }

        let commandVResult = await attemptCommandV(text: trimmedText)
        attempts.append(commandVResult.attempt)
        OtoLogger.log("Injection attempt \(commandVResult.attempt.strategy.rawValue): \(commandVResult.attempt.result.rawValue)", category: .injection, level: .debug)

        switch commandVResult.result {
        case let .success(restoreOutcome):
            finalStrategy = .commandV
            let fallbackWarning: String?
            if focusedElement == nil {
                fallbackWarning = "No focused target detected; used Cmd+V fallback."
            } else {
                fallbackWarning = "AX strategies unavailable; used Cmd+V fallback."
            }

            return .success(
                mergeOutcome(restoreOutcome, fallbackWarning: fallbackWarning),
                diagnostics: buildDiagnostics(
                    strategyChain: strategyChain,
                    attempts: attempts,
                    finalStrategy: finalStrategy,
                    focusedElement: focusedElement,
                    focusWaitMilliseconds: focusResult.waitMilliseconds,
                    preferredAppBundleID: preferredBundleID,
                    preferredAppActivated: preferredActivated
                )
            )
        case let .failure(error):
            return .failure(
                error,
                diagnostics: buildDiagnostics(
                    strategyChain: strategyChain,
                    attempts: attempts,
                    finalStrategy: finalStrategy,
                    focusedElement: focusedElement,
                    focusWaitMilliseconds: focusResult.waitMilliseconds,
                    preferredAppBundleID: preferredBundleID,
                    preferredAppActivated: preferredActivated
                )
            )
        }
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

    private func attemptAXInsertText(text: String, focusedElement: FocusedElementSnapshot) -> InjectionAttempt {
        let result = runtime.insertText(focusedElement.element, text)
        if result == .success {
            return InjectionAttempt(strategy: .axInsertText, result: .success, reason: nil)
        }

        return InjectionAttempt(
            strategy: .axInsertText,
            result: .failed,
            reason: "AXInsertText unavailable (\(result.rawValue))."
        )
    }

    private func attemptAXSetValue(text: String, focusedElement: FocusedElementSnapshot) -> InjectionAttempt {
        let isSettable = runtime.isValueSettable(focusedElement.element)
        let roleEditable = focusedElement.role.map(isEditableRole(_:)) ?? false

        guard isSettable || roleEditable else {
            return InjectionAttempt(
                strategy: .axSetValue,
                result: .failed,
                reason: "Focused target is not editable/settable."
            )
        }

        let result = runtime.setValue(focusedElement.element, text)
        if result == .success {
            return InjectionAttempt(strategy: .axSetValue, result: .success, reason: nil)
        }

        return InjectionAttempt(
            strategy: .axSetValue,
            result: .failed,
            reason: "AX value set failed (\(result.rawValue))."
        )
    }

    private func attemptCommandV(text: String) async -> (attempt: InjectionAttempt, result: Result<TextInjectionOutcome, TextInjectionError>) {
        let backup = pasteboard.snapshot()
        guard pasteboard.setString(text) else {
            return (
                InjectionAttempt(strategy: .commandV, result: .failed, reason: "Unable to write transcript to clipboard."),
                .failure(.eventSourceUnavailable)
            )
        }
        let injectedChangeCount = pasteboard.changeCount

        guard runtime.postCommandV() else {
            return (
                InjectionAttempt(strategy: .commandV, result: .failed, reason: "Unable to post Cmd+V event."),
                .failure(.eventSourceUnavailable)
            )
        }

        await sleepNanos(70_000_000)
        let restoreOutcome = restoreClipboardAfterInjection(snapshot: backup, injectedChangeCount: injectedChangeCount)
        return (
            InjectionAttempt(strategy: .commandV, result: .success, reason: nil),
            .success(restoreOutcome)
        )
    }

    private func waitForFocusedElement(timeout: TimeInterval, pollInterval: TimeInterval) async -> FocusWaitResult {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)

        while Date() <= deadline {
            if let element = runtime.focusedElementProvider() {
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                return FocusWaitResult(
                    focusedElement: FocusedElementSnapshot(
                        element: element,
                        role: runtime.roleProvider(element),
                        subrole: runtime.subroleProvider(element),
                        processID: runtime.processIDProvider(element),
                        waitMilliseconds: elapsed
                    ),
                    waitMilliseconds: elapsed
                )
            }
            await sleepNanos(UInt64(pollInterval * 1_000_000_000))
        }

        return FocusWaitResult(focusedElement: nil, waitMilliseconds: Int(timeout * 1000))
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

    private func buildDiagnostics(
        strategyChain: [InjectionStrategy],
        attempts: [InjectionAttempt],
        finalStrategy: InjectionStrategy?,
        focusedElement: FocusedElementSnapshot?,
        focusWaitMilliseconds: Int,
        preferredAppBundleID: String?,
        preferredAppActivated: Bool
    ) -> TextInjectionDiagnostics {
        TextInjectionDiagnostics(
            strategyChain: strategyChain,
            attempts: attempts,
            finalStrategy: finalStrategy,
            focusedRole: focusedElement?.role,
            focusedSubrole: focusedElement?.subrole,
            focusedProcessID: focusedElement?.processID,
            focusWaitMilliseconds: focusWaitMilliseconds,
            preferredAppBundleID: preferredAppBundleID,
            preferredAppActivated: preferredAppActivated,
            frontmostAppBundleID: runtime.frontmostApplicationProvider()?.bundleIdentifier
        )
    }
}
