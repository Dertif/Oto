import ApplicationServices
import XCTest
@testable import Oto

final class TextInjectionServiceTests: XCTestCase {
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

    func snapshot() -> PasteboardSnapshot {
        .empty
    }

    @discardableResult
    func setString(_ string: String) -> Bool {
        changeCount += 1
        return true
    }

    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        restoreCalled = true
        return restoreResult
    }
}
