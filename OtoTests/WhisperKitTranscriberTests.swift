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

    func testQualityTuningForFastPreset() {
        let tuning = WhisperKitTranscriber.qualityTuning(for: .fast)

        XCTAssertEqual(tuning.requiredSegmentsForConfirmation, 1)
        XCTAssertEqual(tuning.concurrentWorkerCount, 4)
        XCTAssertEqual(tuning.useVAD, false)
    }

    func testQualityTuningForAccuratePreset() {
        let tuning = WhisperKitTranscriber.qualityTuning(for: .accurate)

        XCTAssertEqual(tuning.requiredSegmentsForConfirmation, 2)
        XCTAssertEqual(tuning.concurrentWorkerCount, 2)
        XCTAssertEqual(tuning.useVAD, true)
    }
}
