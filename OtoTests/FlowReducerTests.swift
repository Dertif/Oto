import XCTest
@testable import Oto

final class FlowReducerTests: XCTestCase {
    func testHappyPathTransitions() {
        var snapshot = FlowSnapshot.initial
        let diagnostics = TextRefinementDiagnostics(
            mode: .raw,
            availability: "Available",
            latency: nil,
            fallbackReason: "refinement_mode_raw",
            outputSource: .raw
        )

        snapshot = FlowReducer.reduce(
            snapshot: snapshot,
            event: .startRequested(backend: .appleSpeech, message: "Listening")
        )
        XCTAssertEqual(snapshot.phase, .listening)

        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .stopRequested(message: "Transcribing"))
        XCTAssertEqual(snapshot.phase, .transcribing)

        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .transcriptionSucceeded(text: "hello"))
        XCTAssertEqual(snapshot.phase, .refining)

        snapshot = FlowReducer.reduce(
            snapshot: snapshot,
            event: .refinementSkipped(text: "hello", message: "Using raw transcript.", diagnostics: diagnostics)
        )
        XCTAssertEqual(snapshot.phase, .injecting)

        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .injectionSucceeded(message: "Injected"))
        XCTAssertEqual(snapshot.phase, .completed)
    }

    func testInvalidTransitionReturnsUnchangedSnapshot() {
        let previousHandler = FlowReducerDiagnostics.invalidTransitionHandler
        FlowReducerDiagnostics.invalidTransitionHandler = nil
        defer { FlowReducerDiagnostics.invalidTransitionHandler = previousHandler }

        let initial = FlowSnapshot.initial
        let reduced = FlowReducer.reduce(snapshot: initial, event: .stopRequested(message: "x"))

        XCTAssertEqual(reduced, initial)
    }

    func testTerminalResetAllowsRetry() {
        var snapshot = FlowSnapshot.initial
        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .startRequested(backend: .whisper, message: "Listening"))
        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .captureFailed(message: "boom"))
        XCTAssertEqual(snapshot.phase, .failed)

        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .resetToIdle(message: "Ready"))
        XCTAssertEqual(snapshot.phase, .idle)
        XCTAssertEqual(snapshot.statusMessage, "Ready")

        snapshot = FlowReducer.reduce(snapshot: snapshot, event: .startRequested(backend: .whisper, message: "Listening"))
        XCTAssertEqual(snapshot.phase, .listening)
    }

    func testInvalidTransitionInvokesDiagnosticsHandler() {
        var captured: String?
        let previousHandler = FlowReducerDiagnostics.invalidTransitionHandler
        FlowReducerDiagnostics.invalidTransitionHandler = { message in
            captured = message
        }
        defer { FlowReducerDiagnostics.invalidTransitionHandler = previousHandler }

        let initial = FlowSnapshot.initial
        _ = FlowReducer.reduce(snapshot: initial, event: .stopRequested(message: "x"))

        XCTAssertNotNil(captured)
    }
}
