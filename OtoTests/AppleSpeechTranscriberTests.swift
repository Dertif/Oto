import XCTest
@testable import Oto

@MainActor
final class AppleSpeechTranscriberTests: XCTestCase {
    func testClassifyTerminalErrorTreatsStopNoiseAsExpectedWhenUsableTranscriptExists() {
        let error = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 602,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )

        let classification = AppleSpeechTranscriber.classifyTerminalError(
            error: error,
            isStopping: true,
            hasUsableTranscript: true,
            hasFinalResult: false
        )

        XCTAssertEqual(classification, .expectedStopNoise)
    }

    func testClassifyTerminalErrorTreatsNoSpeechAtStopAsExpectedNoise() {
        let error = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 602,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )

        let classification = AppleSpeechTranscriber.classifyTerminalError(
            error: error,
            isStopping: true,
            hasUsableTranscript: false,
            hasFinalResult: false
        )

        XCTAssertEqual(classification, .expectedStopNoise)
    }

    func testClassifyTerminalErrorReturnsRealFailureForNonStopErrorWithoutTranscript() {
        let error = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Mic disconnected"]
        )

        let classification = AppleSpeechTranscriber.classifyTerminalError(
            error: error,
            isStopping: false,
            hasUsableTranscript: false,
            hasFinalResult: false
        )

        XCTAssertEqual(classification, .realFailure)
    }

    func testClassifyTerminalErrorReturnsRealFailureDuringActiveDictationAfterPartialText() {
        let error = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 111,
            userInfo: [NSLocalizedDescriptionKey: "Recognizer connection interrupted"]
        )

        let classification = AppleSpeechTranscriber.classifyTerminalError(
            error: error,
            isStopping: false,
            hasUsableTranscript: true,
            hasFinalResult: false
        )

        XCTAssertEqual(classification, .realFailure)
    }

    func testClassifyTerminalErrorTreatsPostFinalErrorAsUsableFinal() {
        let error = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 602,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )

        let classification = AppleSpeechTranscriber.classifyTerminalError(
            error: error,
            isStopping: false,
            hasUsableTranscript: true,
            hasFinalResult: true
        )

        XCTAssertEqual(classification, .usableFinal)
    }
}
