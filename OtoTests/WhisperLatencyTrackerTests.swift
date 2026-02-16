import XCTest
@testable import Oto

final class WhisperLatencyTrackerTests: XCTestCase {
    func testStreamingRunCapturesAllDurations() {
        let tracker = WhisperLatencyTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        let firstPartial = start.addingTimeInterval(0.8)
        let stop = start.addingTimeInterval(2.5)
        let finish = start.addingTimeInterval(3.1)

        tracker.beginRun(usingStreaming: true, at: start)
        tracker.markFirstPartial(at: firstPartial)
        tracker.markStopRequested(at: stop)

        guard let metrics = tracker.finish(at: finish) else {
            return XCTFail("Expected latency metrics for streaming run")
        }
        guard let timeToFirstPartial = metrics.timeToFirstPartial else {
            return XCTFail("Expected time-to-first-partial for streaming run")
        }
        guard let stopToFinalTranscript = metrics.stopToFinalTranscript else {
            return XCTFail("Expected stop-to-final for streaming run")
        }

        XCTAssertEqual(metrics.usedStreaming, true)
        XCTAssertEqual(timeToFirstPartial, 0.8, accuracy: 0.0001)
        XCTAssertEqual(stopToFinalTranscript, 0.6, accuracy: 0.0001)
        XCTAssertEqual(metrics.totalDuration, 3.1, accuracy: 0.0001)
    }

    func testFileRunLeavesTimeToFirstPartialNil() {
        let tracker = WhisperLatencyTracker()
        let start = Date(timeIntervalSince1970: 2_000)
        let stop = start.addingTimeInterval(1.2)
        let finish = start.addingTimeInterval(1.8)

        tracker.beginRun(usingStreaming: false, at: start)
        tracker.markStopRequested(at: stop)

        guard let metrics = tracker.finish(at: finish) else {
            return XCTFail("Expected latency metrics for file run")
        }
        guard let stopToFinalTranscript = metrics.stopToFinalTranscript else {
            return XCTFail("Expected stop-to-final for file run")
        }

        XCTAssertEqual(metrics.usedStreaming, false)
        XCTAssertNil(metrics.timeToFirstPartial)
        XCTAssertEqual(stopToFinalTranscript, 0.6, accuracy: 0.0001)
        XCTAssertEqual(metrics.totalDuration, 1.8, accuracy: 0.0001)
    }

    func testFirstPartialIsCapturedOnlyOnce() {
        let tracker = WhisperLatencyTracker()
        let start = Date(timeIntervalSince1970: 3_000)

        tracker.beginRun(usingStreaming: true, at: start)
        tracker.markFirstPartial(at: start.addingTimeInterval(0.4))
        tracker.markFirstPartial(at: start.addingTimeInterval(1.1))

        guard let metrics = tracker.finish(at: start.addingTimeInterval(2.0)) else {
            return XCTFail("Expected latency metrics after finish")
        }
        guard let timeToFirstPartial = metrics.timeToFirstPartial else {
            return XCTFail("Expected first partial latency")
        }

        XCTAssertEqual(timeToFirstPartial, 0.4, accuracy: 0.0001)
    }

    func testFinishWithoutRunReturnsNil() {
        let tracker = WhisperLatencyTracker()
        XCTAssertNil(tracker.finish())
    }
}
