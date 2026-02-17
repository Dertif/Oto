import ApplicationServices
import XCTest
@testable import Oto

final class TextInjectionServiceTests: XCTestCase {
    @MainActor
    func testStrategyOrderFallsBackFromAXToCommandV() async {
        let element = AXUIElementCreateSystemWide()
        var callOrder: [String] = []
        let pasteboard = FakePasteboard()

        let runtime = TextInjectionRuntime(
            focusedElementProvider: { element },
            roleProvider: { _ in "AXTextField" },
            subroleProvider: { _ in nil },
            processIDProvider: { _ in 111 },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in
                callOrder.append("insert")
                return .actionUnsupported
            },
            setValue: { _, _ in
                callOrder.append("set")
                return .cannotComplete
            },
            isValueSettable: { _ in true },
            postCommandV: {
                callOrder.append("cmdv")
                return true
            }
        )

        let service = TextInjectionService(runtime: runtime, pasteboard: pasteboard, sleepNanos: { _ in })
        let report = await service.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: true
        ))

        XCTAssertEqual(callOrder, ["insert", "set", "cmdv"])
        XCTAssertNotNil(report.outcome)
        XCTAssertNil(report.error)
        XCTAssertEqual(report.diagnostics.finalStrategy, .commandV)
    }

    @MainActor
    func testStrategyShortCircuitsAfterAXInsertTextSuccess() async {
        let element = AXUIElementCreateSystemWide()
        var callOrder: [String] = []

        let runtime = TextInjectionRuntime(
            focusedElementProvider: { element },
            roleProvider: { _ in "AXTextField" },
            subroleProvider: { _ in nil },
            processIDProvider: { _ in 111 },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in
                callOrder.append("insert")
                return .success
            },
            setValue: { _, _ in
                callOrder.append("set")
                return .success
            },
            isValueSettable: { _ in true },
            postCommandV: {
                callOrder.append("cmdv")
                return true
            }
        )

        let service = TextInjectionService(runtime: runtime, sleepNanos: { _ in })
        let report = await service.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: true
        ))

        XCTAssertEqual(callOrder, ["insert"])
        XCTAssertEqual(report.diagnostics.finalStrategy, .axInsertText)
        XCTAssertEqual(report.diagnostics.attempts.count, 1)
    }

    @MainActor
    func testCommandVSkippedWhenDisabled() async {
        let element = AXUIElementCreateSystemWide()
        var didPostCommandV = false

        let runtime = TextInjectionRuntime(
            focusedElementProvider: { element },
            roleProvider: { _ in "AXButton" },
            subroleProvider: { _ in nil },
            processIDProvider: { _ in 111 },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in .actionUnsupported },
            setValue: { _, _ in .cannotComplete },
            isValueSettable: { _ in false },
            postCommandV: {
                didPostCommandV = true
                return true
            }
        )

        let service = TextInjectionService(runtime: runtime, sleepNanos: { _ in })
        let report = await service.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: false
        ))

        XCTAssertFalse(didPostCommandV)
        XCTAssertNil(report.outcome)
        XCTAssertEqual(report.error, .focusedElementNotEditable)
        XCTAssertEqual(report.diagnostics.attempts.last?.strategy, .commandV)
        XCTAssertEqual(report.diagnostics.attempts.last?.result, .skipped)
    }

    @MainActor
    func testClipboardUsedOnlyForCommandVPath() async {
        let element = AXUIElementCreateSystemWide()
        let pasteboardAXOnly = FakePasteboard()
        let pasteboardFallback = FakePasteboard()

        let axOnlyRuntime = TextInjectionRuntime(
            focusedElementProvider: { element },
            roleProvider: { _ in "AXTextField" },
            subroleProvider: { _ in nil },
            processIDProvider: { _ in 111 },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in .success },
            setValue: { _, _ in .success },
            isValueSettable: { _ in true },
            postCommandV: { true }
        )

        let fallbackRuntime = TextInjectionRuntime(
            focusedElementProvider: { element },
            roleProvider: { _ in "AXTextField" },
            subroleProvider: { _ in nil },
            processIDProvider: { _ in 111 },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in .actionUnsupported },
            setValue: { _, _ in .cannotComplete },
            isValueSettable: { _ in false },
            postCommandV: { true }
        )

        let axOnlyService = TextInjectionService(runtime: axOnlyRuntime, pasteboard: pasteboardAXOnly, sleepNanos: { _ in })
        let fallbackService = TextInjectionService(runtime: fallbackRuntime, pasteboard: pasteboardFallback, sleepNanos: { _ in })

        _ = await axOnlyService.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: true
        ))
        _ = await fallbackService.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: true
        ))

        XCTAssertEqual(pasteboardAXOnly.snapshotCallCount, 0)
        XCTAssertEqual(pasteboardAXOnly.setStringCallCount, 0)
        XCTAssertEqual(pasteboardFallback.snapshotCallCount, 1)
        XCTAssertEqual(pasteboardFallback.setStringCallCount, 1)
    }

    @MainActor
    func testFocusStabilizationTimeoutProducesDeterministicFailure() async {
        let runtime = TextInjectionRuntime(
            focusedElementProvider: { nil },
            roleProvider: { _ in nil },
            subroleProvider: { _ in nil },
            processIDProvider: { _ in nil },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in .success },
            setValue: { _, _ in .success },
            isValueSettable: { _ in true },
            postCommandV: { true }
        )

        let service = TextInjectionService(runtime: runtime, sleepNanos: { _ in })
        let report = await service.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: false
        ))

        XCTAssertNil(report.outcome)
        XCTAssertEqual(report.error, .focusStabilizationTimedOut)
        XCTAssertEqual(report.diagnostics.focusWaitMilliseconds, 900)
    }

    @MainActor
    func testDelayedFocusAvailabilityEventuallySucceeds() async {
        let element = AXUIElementCreateSystemWide()
        var probeCount = 0

        let runtime = TextInjectionRuntime(
            focusedElementProvider: {
                probeCount += 1
                return probeCount < 3 ? nil : element
            },
            roleProvider: { _ in "AXTextField" },
            subroleProvider: { _ in "AXStandardWindow" },
            processIDProvider: { _ in 999 },
            activatePreferredApp: { _ in true },
            frontmostApplicationProvider: { nil },
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
            insertText: { _, _ in .success },
            setValue: { _, _ in .success },
            isValueSettable: { _ in true },
            postCommandV: { true }
        )

        let service = TextInjectionService(runtime: runtime, sleepNanos: { _ in })
        let report = await service.inject(request: TextInjectionRequest(
            text: "hello",
            preferredApplication: nil,
            allowCommandVFallback: false
        ))

        XCTAssertNotNil(report.outcome)
        XCTAssertNil(report.error)
        XCTAssertEqual(report.diagnostics.finalStrategy, .axInsertText)
        XCTAssertGreaterThanOrEqual(report.diagnostics.focusWaitMilliseconds, 0)
    }

    @MainActor
    func testEditableRolesIncludeCoreTextRoles() {
        let service = TextInjectionService()

        XCTAssertTrue(service.isEditableRole(kAXTextFieldRole as String))
        XCTAssertTrue(service.isEditableRole(kAXTextAreaRole as String))
        XCTAssertTrue(service.isEditableRole("AXSearchField"))
    }

    @MainActor
    func testEditableRolesRejectNonTextRole() {
        let service = TextInjectionService()

        XCTAssertFalse(service.isEditableRole(kAXButtonRole as String))
    }

    @MainActor
    func testRestoreClipboardAfterInjectionSuccess() {
        let pasteboard = FakePasteboard()
        pasteboard.changeCount = 7
        pasteboard.restoreResult = true

        let service = TextInjectionService(pasteboard: pasteboard, sleepNanos: { _ in })
        let outcome = service.restoreClipboardAfterInjection(snapshot: .empty, injectedChangeCount: 7)

        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(pasteboard.restoreCalled)
    }

    @MainActor
    func testRestoreClipboardAfterInjectionSkippedWhenClipboardChanged() {
        let pasteboard = FakePasteboard()
        pasteboard.changeCount = 10
        pasteboard.restoreResult = true

        let service = TextInjectionService(pasteboard: pasteboard, sleepNanos: { _ in })
        let outcome = service.restoreClipboardAfterInjection(snapshot: .empty, injectedChangeCount: 9)

        XCTAssertEqual(outcome, .successWithWarning("Clipboard changed during injection; restore skipped."))
        XCTAssertFalse(pasteboard.restoreCalled)
    }

    @MainActor
    func testRestoreClipboardAfterInjectionWarningWhenRestoreFails() {
        let pasteboard = FakePasteboard()
        pasteboard.changeCount = 4
        pasteboard.restoreResult = false

        let service = TextInjectionService(pasteboard: pasteboard, sleepNanos: { _ in })
        let outcome = service.restoreClipboardAfterInjection(snapshot: .empty, injectedChangeCount: 4)

        XCTAssertEqual(outcome, .successWithWarning("Transcript injected, but clipboard could not be restored."))
        XCTAssertTrue(pasteboard.restoreCalled)
    }
}

private final class FakePasteboard: PasteboardAccessing {
    var changeCount: Int = 0
    var restoreResult = true
    var restoreCalled = false
    var snapshotCallCount = 0
    var setStringCallCount = 0

    func snapshot() -> PasteboardSnapshot {
        snapshotCallCount += 1
        return .empty
    }

    @discardableResult
    func setString(_ string: String) -> Bool {
        setStringCallCount += 1
        changeCount += 1
        return true
    }

    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        restoreCalled = true
        return restoreResult
    }
}
