import XCTest
@testable import Oto

@MainActor
final class RefinementLatencyRecorderTests: XCTestCase {
    func testPercentileInterpolation() {
        let values: [TimeInterval] = [0.2, 0.4, 0.6, 0.8, 1.0]

        XCTAssertEqual(RefinementLatencyRecorder.percentile(0.50, from: values), 0.6, accuracy: 0.0001)
        XCTAssertEqual(RefinementLatencyRecorder.percentile(0.95, from: values), 0.96, accuracy: 0.0001)
    }

    func testAggregatesByBackendAndMode() {
        let recorder = RefinementLatencyRecorder(maxSamplesPerKey: 20)

        recorder.record(RefinementLatencyMetrics(
            backend: .appleSpeech,
            mode: .enhanced,
            refinementLatency: 0.9,
            stopToFinalOverhead: 1.1,
            recordedAt: Date()
        ))
        recorder.record(RefinementLatencyMetrics(
            backend: .appleSpeech,
            mode: .enhanced,
            refinementLatency: 1.1,
            stopToFinalOverhead: 1.3,
            recordedAt: Date()
        ))
        recorder.record(RefinementLatencyMetrics(
            backend: .whisper,
            mode: .enhanced,
            refinementLatency: 1.2,
            stopToFinalOverhead: 1.6,
            recordedAt: Date()
        ))

        let aggregates = recorder.aggregates()
        XCTAssertEqual(aggregates.count, 2)

        let apple = aggregates.first { $0.backend == .appleSpeech }
        XCTAssertEqual(apple?.sampleCount, 2)
        XCTAssertEqual(apple?.refinementLatency.p50 ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(apple?.stopToFinalOverhead.p95 ?? 0, 1.29, accuracy: 0.0001)
    }

    func testSummaryWithNoRuns() {
        let recorder = RefinementLatencyRecorder()
        XCTAssertEqual(recorder.summary(), "Refinement P50/P95: no runs yet.")
    }
}
