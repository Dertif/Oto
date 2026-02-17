import Foundation

@MainActor
final class RefinementLatencyRecorder: RefinementLatencyRecording {
    private struct Key: Hashable {
        let backend: STTBackend
        let mode: TextRefinementMode
    }

    private let maxSamplesPerKey: Int
    private var samplesByKey: [Key: [RefinementLatencyMetrics]] = [:]

    init(maxSamplesPerKey: Int = 100) {
        self.maxSamplesPerKey = max(1, maxSamplesPerKey)
    }

    func record(_ metrics: RefinementLatencyMetrics) {
        let key = Key(backend: metrics.backend, mode: metrics.mode)
        var samples = samplesByKey[key, default: []]
        samples.append(metrics)
        if samples.count > maxSamplesPerKey {
            samples.removeFirst(samples.count - maxSamplesPerKey)
        }
        samplesByKey[key] = samples
    }

    func aggregates() -> [RefinementLatencyAggregate] {
        let keys = samplesByKey.keys.sorted { lhs, rhs in
            if lhs.backend.rawValue == rhs.backend.rawValue {
                return lhs.mode.rawValue < rhs.mode.rawValue
            }
            return lhs.backend.rawValue < rhs.backend.rawValue
        }

        return keys.compactMap { key in
            aggregate(for: key)
        }
    }

    func summary() -> String {
        let rows = aggregates()
        guard !rows.isEmpty else {
            return "Refinement P50/P95: no runs yet."
        }
        return "Refinement P50/P95 - " + rows.map(\.summaryLine).joined(separator: " | ")
    }

    private func aggregate(for key: Key) -> RefinementLatencyAggregate? {
        guard let samples = samplesByKey[key], !samples.isEmpty else {
            return nil
        }

        return RefinementLatencyAggregate(
            backend: key.backend,
            mode: key.mode,
            sampleCount: samples.count,
            refinementLatency: percentiles(for: samples.map(\.refinementLatency)),
            stopToFinalOverhead: percentiles(for: samples.map(\.stopToFinalOverhead))
        )
    }

    private func percentiles(for values: [TimeInterval]) -> RefinementLatencyPercentiles {
        RefinementLatencyPercentiles(
            p50: Self.percentile(0.50, from: values),
            p95: Self.percentile(0.95, from: values)
        )
    }

    static func percentile(_ p: Double, from values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else {
            return 0
        }

        let sorted = values.sorted()
        if sorted.count == 1 {
            return sorted[0]
        }

        let boundedP = min(max(p, 0), 1)
        let rank = boundedP * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper {
            return sorted[lower]
        }
        let weight = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }
}
