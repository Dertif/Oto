import XCTest
@testable import Oto

final class TranscriptNormalizerTests: XCTestCase {
    private let normalizer = TranscriptNormalizer.shared

    func testNormalizeRemovesWhisperTokensAndCollapsesWhitespace() {
        let raw = "<|startoftranscript|>   Hello   world  <|endoftext|>"
        XCTAssertEqual(normalizer.normalize(raw), "Hello world")
    }

    func testNormalizePunctuationSpacing() {
        let raw = "Hello ,world!How are you ?I am fine."
        XCTAssertEqual(normalizer.normalize(raw), "Hello, world! How are you? I am fine.")
    }

    func testNormalizePreservesDecimalPoints() {
        let raw = "The value is 3.14 and version is 2.0"
        XCTAssertEqual(normalizer.normalize(raw), "The value is 3.14 and version is 2.0")
    }

    func testNormalizeDoesNotInsertSpacesInNumericOrClockTokens() {
        let raw = "Use 3,14 and meet at 12:30"
        XCTAssertEqual(normalizer.normalize(raw), "Use 3,14 and meet at 12:30")
    }

    func testNormalizeDoesNotBreakUrlsOrIdentifiersWithColonAndPeriod() {
        let raw = "Open https://example.com/path:80 now"
        XCTAssertEqual(normalizer.normalize(raw), "Open https://example.com/path:80 now")
    }
}
