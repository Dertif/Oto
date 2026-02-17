import XCTest
@testable import Oto

@MainActor
final class LatencyMetricsRecorderTests: XCTestCase {
    func testPercentileInterpolation() {
        let values: [TimeInterval] = [1, 2, 3, 4, 5]

        XCTAssertEqual(LatencyMetricsRecorder.percentile(0.50, from: values), 3, accuracy: 0.0001)
        XCTAssertEqual(LatencyMetricsRecorder.percentile(0.95, from: values), 4.8, accuracy: 0.0001)
    }

    func testAggregatesByBackend() {
        let recorder = LatencyMetricsRecorder(maxSamplesPerBackend: 20)

        recorder.record(BackendLatencyMetrics(
            backend: .appleSpeech,
            usedStreaming: true,
            timeToFirstPartial: 0.20,
            stopToFinal: 0.40,
            total: 1.10,
            recordedAt: Date()
        ))
        recorder.record(BackendLatencyMetrics(
            backend: .appleSpeech,
            usedStreaming: true,
            timeToFirstPartial: 0.30,
            stopToFinal: 0.60,
            total: 1.40,
            recordedAt: Date()
        ))
        recorder.record(BackendLatencyMetrics(
            backend: .whisper,
            usedStreaming: true,
            timeToFirstPartial: 0.80,
            stopToFinal: 0.70,
            total: 3.80,
            recordedAt: Date()
        ))

        let aggregates = recorder.aggregates()
        XCTAssertEqual(aggregates.count, 2)

        let apple = aggregates.first { $0.backend == .appleSpeech }
        XCTAssertEqual(apple?.sampleCount, 2)
        XCTAssertEqual(apple?.total.p50 ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(apple?.stopToFinal?.p95 ?? 0, 0.59, accuracy: 0.0001)

        let whisper = aggregates.first { $0.backend == .whisper }
        XCTAssertEqual(whisper?.sampleCount, 1)
        XCTAssertEqual(whisper?.timeToFirstPartial?.p50 ?? 0, 0.80, accuracy: 0.0001)
    }

    func testSummaryWithNoRuns() {
        let recorder = LatencyMetricsRecorder()
        XCTAssertEqual(recorder.summary(), "Latency P50/P95: no runs yet.")
    }
}
