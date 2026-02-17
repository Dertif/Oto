import Foundation

@MainActor
protocol LatencyMetricsRecording: AnyObject {
    func record(_ metrics: BackendLatencyMetrics)
    func summary() -> String
    func aggregates() -> [BackendLatencyAggregate]
}

@MainActor
final class LatencyMetricsRecorder: LatencyMetricsRecording {
    private let maxSamplesPerBackend: Int
    private var samplesByBackend: [STTBackend: [BackendLatencyMetrics]] = [:]

    init(maxSamplesPerBackend: Int = 100) {
        self.maxSamplesPerBackend = max(1, maxSamplesPerBackend)
    }

    func record(_ metrics: BackendLatencyMetrics) {
        var samples = samplesByBackend[metrics.backend, default: []]
        samples.append(metrics)
        if samples.count > maxSamplesPerBackend {
            samples.removeFirst(samples.count - maxSamplesPerBackend)
        }
        samplesByBackend[metrics.backend] = samples
    }

    func aggregates() -> [BackendLatencyAggregate] {
        STTBackend.allCases.compactMap { backend in
            aggregate(for: backend)
        }
    }

    func summary() -> String {
        let rows = aggregates()
        guard !rows.isEmpty else {
            return "Latency P50/P95: no runs yet."
        }
        return "Latency P50/P95 - " + rows.map(\.summaryLine).joined(separator: " | ")
    }

    private func aggregate(for backend: STTBackend) -> BackendLatencyAggregate? {
        guard let samples = samplesByBackend[backend], !samples.isEmpty else {
            return nil
        }

        guard let total = percentiles(for: samples.map(\.total)) else {
            return nil
        }

        return BackendLatencyAggregate(
            backend: backend,
            sampleCount: samples.count,
            timeToFirstPartial: percentiles(for: samples.compactMap(\.timeToFirstPartial)),
            stopToFinal: percentiles(for: samples.compactMap(\.stopToFinal)),
            total: total
        )
    }

    private func percentiles(for values: [TimeInterval]) -> BackendLatencyPercentiles? {
        guard !values.isEmpty else {
            return nil
        }
        return BackendLatencyPercentiles(
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
