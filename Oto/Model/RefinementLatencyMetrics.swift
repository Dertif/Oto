import Foundation

struct RefinementLatencyMetrics: Equatable {
    let backend: STTBackend
    let mode: TextRefinementMode
    let refinementLatency: TimeInterval
    let stopToFinalOverhead: TimeInterval
    let recordedAt: Date

    var runSummary: String {
        "\(backend.rawValue) \(mode.rawValue) refinement - latency: \(Self.format(refinementLatency)), overhead: \(Self.format(stopToFinalOverhead))"
    }

    static func format(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }
}

struct RefinementLatencyPercentiles: Equatable {
    let p50: TimeInterval
    let p95: TimeInterval

    var summary: String {
        "\(RefinementLatencyMetrics.format(p50))/\(RefinementLatencyMetrics.format(p95))"
    }
}

struct RefinementLatencyAggregate: Equatable {
    let backend: STTBackend
    let mode: TextRefinementMode
    let sampleCount: Int
    let refinementLatency: RefinementLatencyPercentiles
    let stopToFinalOverhead: RefinementLatencyPercentiles

    var summaryLine: String {
        "\(backend.rawValue) \(mode.rawValue) [n=\(sampleCount)]: refine \(refinementLatency.summary), overhead \(stopToFinalOverhead.summary)"
    }
}
