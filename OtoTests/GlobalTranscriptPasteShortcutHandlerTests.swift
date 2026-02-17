import XCTest
@testable import Oto

@MainActor
final class GlobalTranscriptPasteShortcutHandlerTests: XCTestCase {
    func testNoTranscriptReturnsNoTranscript() async {
        let clipboard = SessionTranscriptClipboard()
        let pasteService = MockCommandVPasteService()
        pasteService.outcome = .noTranscript

        let handler = GlobalTranscriptPasteShortcutHandler(
            clipboard: clipboard,
            pasteService: pasteService
        )

        let outcome = await handler.handleHotkeyPress()

        XCTAssertEqual(outcome, .noTranscript)
        XCTAssertNil(pasteService.lastTranscript)
    }

    func testPastedTranscriptUsesClipboardValue() async {
        let clipboard = SessionTranscriptClipboard()
        clipboard.update(with: "latest transcript")
        let pasteService = MockCommandVPasteService()
        pasteService.outcome = .pasted

        let handler = GlobalTranscriptPasteShortcutHandler(
            clipboard: clipboard,
            pasteService: pasteService
        )

        let outcome = await handler.handleHotkeyPress()

        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(pasteService.lastTranscript, "latest transcript")
    }

    func testCopiedOnlyOutcomeIsReturned() async {
        let clipboard = SessionTranscriptClipboard()
        clipboard.update(with: "latest transcript")
        let pasteService = MockCommandVPasteService()
        pasteService.outcome = .copiedOnly("Cmd+V unavailable.")

        let handler = GlobalTranscriptPasteShortcutHandler(
            clipboard: clipboard,
            pasteService: pasteService
        )

        let outcome = await handler.handleHotkeyPress()

        XCTAssertEqual(outcome, .copiedOnly("Cmd+V unavailable."))
    }
}

@MainActor
private final class MockCommandVPasteService: CommandVPasting {
    var outcome: CommandVPasteOutcome = .noTranscript
    private(set) var lastTranscript: String?

    func pasteLatestTranscript(_ transcript: String?) async -> CommandVPasteOutcome {
        lastTranscript = transcript
        return outcome
    }
}
