import XCTest
@testable import Oto

final class WhisperKitTranscriberTests: XCTestCase {
    func testSanitizeTranscriptionTextRemovesSpecialTokens() {
        let raw = "<|startoftranscript|><|en|><|transcribe|><|notimestamps|> Hello   world <|endoftext|>"

        let sanitized = WhisperKitTranscriber.sanitizeTranscriptionText(raw)

        XCTAssertEqual(sanitized, "Hello world")
    }

    func testSanitizeTranscriptionTextReturnsEmptyWhenOnlyTokens() {
        let raw = "<|startoftranscript|> <|en|> <|endoftext|>"

        let sanitized = WhisperKitTranscriber.sanitizeTranscriptionText(raw)

        XCTAssertTrue(sanitized.isEmpty)
    }
}
