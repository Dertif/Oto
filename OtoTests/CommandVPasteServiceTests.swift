import XCTest
@testable import Oto

@MainActor
final class CommandVPasteServiceTests: XCTestCase {
    func testNoTranscriptReturnsNoTranscriptOutcome() async {
        let pasteboard = FakeCommandVPasteboard()
        let service = CommandVPasteService(
            pasteboard: pasteboard,
            postCommandV: { true },
            sleepNanos: { _ in }
        )

        let outcome = await service.pasteLatestTranscript(nil)

        XCTAssertEqual(outcome, .noTranscript)
        XCTAssertEqual(pasteboard.setStringCallCount, 0)
    }

    func testFailedCommandVFallsBackToClipboardOnly() async {
        let pasteboard = FakeCommandVPasteboard()
        let service = CommandVPasteService(
            pasteboard: pasteboard,
            postCommandV: { false },
            sleepNanos: { _ in }
        )

        let outcome = await service.pasteLatestTranscript("hello")

        XCTAssertEqual(outcome, .copiedOnly("Cmd+V event could not be generated; transcript copied to clipboard."))
        XCTAssertEqual(pasteboard.setStringCallCount, 1)
        XCTAssertFalse(pasteboard.restoreCalled)
    }

    func testPasteSuccessRestoresClipboard() async {
        let pasteboard = FakeCommandVPasteboard()
        pasteboard.changeCount = 2
        pasteboard.restoreResult = true
        let service = CommandVPasteService(
            pasteboard: pasteboard,
            postCommandV: { true },
            sleepNanos: { _ in }
        )

        let outcome = await service.pasteLatestTranscript("hello")

        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(pasteboard.setStringCallCount, 1)
        XCTAssertTrue(pasteboard.restoreCalled)
    }

    func testPasteSkipsRestoreWhenClipboardChanges() async {
        let pasteboard = FakeCommandVPasteboard()
        pasteboard.changeCount = 3
        let service = CommandVPasteService(
            pasteboard: pasteboard,
            postCommandV: { true },
            sleepNanos: { _ in
                // Simulate external clipboard change after Cmd+V and before restore.
                pasteboard.changeCount += 3
            }
        )

        let outcome = await service.pasteLatestTranscript("hello")

        XCTAssertEqual(outcome, .pastedWithWarning("Clipboard changed during paste; restore skipped."))
        XCTAssertFalse(pasteboard.restoreCalled)
    }
}

private final class FakeCommandVPasteboard: PasteboardAccessing {
    var changeCount: Int = 0
    var restoreResult = true
    var restoreCalled = false
    var setStringCallCount = 0
    var onSetString: (() -> Void)?

    func snapshot() -> PasteboardSnapshot {
        .empty
    }

    @discardableResult
    func setString(_ string: String) -> Bool {
        setStringCallCount += 1
        changeCount += 1
        onSetString?()
        return true
    }

    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        restoreCalled = true
        return restoreResult
    }
}
