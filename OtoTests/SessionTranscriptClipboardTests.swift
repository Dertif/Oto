import XCTest
@testable import Oto

@MainActor
final class SessionTranscriptClipboardTests: XCTestCase {
    func testUpdateStoresTrimmedTranscript() {
        let clipboard = SessionTranscriptClipboard()

        clipboard.update(with: "  hello world  ")

        XCTAssertEqual(clipboard.latestTranscript, "hello world")
        XCTAssertNotNil(clipboard.updatedAt)
    }

    func testUpdateIgnoresEmptyTranscript() {
        let clipboard = SessionTranscriptClipboard()
        clipboard.update(with: "hello")

        clipboard.update(with: "   ")

        XCTAssertEqual(clipboard.latestTranscript, "hello")
    }

    func testClearRemovesStoredTranscript() {
        let clipboard = SessionTranscriptClipboard()
        clipboard.update(with: "hello")

        clipboard.clear()

        XCTAssertNil(clipboard.latestTranscript)
        XCTAssertNil(clipboard.updatedAt)
    }
}
