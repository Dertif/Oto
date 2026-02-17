import XCTest
@testable import Oto

final class AppStateProjectionTests: XCTestCase {
    func testListeningMapsToRecordingVisualState() {
        var snapshot = FlowSnapshot.initial
        snapshot.phase = .listening

        let projection = AppStateMapper.map(snapshot: snapshot)

        XCTAssertEqual(projection.reliabilityState, .listening)
        XCTAssertTrue(projection.isRecording)
        XCTAssertFalse(projection.isProcessing)
        XCTAssertEqual(projection.visualState, .recording)
    }

    func testCompletedAfterInjectionMapsToInjectedReliability() {
        var snapshot = FlowSnapshot.initial
        snapshot.phase = .completed
        snapshot.lastEvent = .injectionSucceeded(message: "Injected")

        let projection = AppStateMapper.map(snapshot: snapshot)

        XCTAssertEqual(projection.reliabilityState, .injected)
        XCTAssertEqual(projection.visualState, .idle)
    }

    func testCompletedWithoutInjectionMapsToReady() {
        var snapshot = FlowSnapshot.initial
        snapshot.phase = .completed
        snapshot.lastEvent = .injectionSkipped(message: "Saved")

        let projection = AppStateMapper.map(snapshot: snapshot)

        XCTAssertEqual(projection.reliabilityState, .ready)
    }

    func testProjectionKeepsSeparateArtifactUrls() {
        let primaryURL = URL(fileURLWithPath: "/tmp/primary.txt")
        let rawURL = URL(fileURLWithPath: "/tmp/raw.txt")
        let refinedURL = URL(fileURLWithPath: "/tmp/refined.txt")
        let failureURL = URL(fileURLWithPath: "/tmp/failure.txt")

        var snapshot = FlowSnapshot.initial
        snapshot.artifacts = TranscriptArtifacts(
            primaryURL: primaryURL,
            rawURL: rawURL,
            refinedURL: refinedURL,
            failureContextURL: failureURL
        )

        let projection = AppStateMapper.map(snapshot: snapshot)

        XCTAssertEqual(projection.primaryTranscriptURL, primaryURL)
        XCTAssertEqual(projection.rawTranscriptURL, rawURL)
        XCTAssertEqual(projection.refinedTranscriptURL, refinedURL)
        XCTAssertEqual(projection.failureContextURL, failureURL)
    }

    func testRefiningPhaseMapsToProcessingState() {
        var snapshot = FlowSnapshot.initial
        snapshot.phase = .refining

        let projection = AppStateMapper.map(snapshot: snapshot)

        XCTAssertEqual(projection.reliabilityState, .transcribing)
        XCTAssertTrue(projection.isProcessing)
        XCTAssertFalse(projection.isRecording)
        XCTAssertEqual(projection.visualState, .processing)
    }
}
