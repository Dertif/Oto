import Foundation

struct BackendLatencyMetrics: Equatable {
    let backend: STTBackend
    let usedStreaming: Bool
    let timeToFirstPartial: TimeInterval?
    let stopToFinal: TimeInterval?
    let total: TimeInterval
    let recordedAt: Date

    var runSummary: String {
        let mode = usedStreaming ? "streaming" : "file"
        return "\(backend.rawValue) latency (\(mode)) - TTFP: \(Self.format(timeToFirstPartial)), Stop->Final: \(Self.format(stopToFinal)), Total: \(Self.format(total))"
    }

    static func format(_ value: TimeInterval?) -> String {
        guard let value else {
            return "n/a"
        }
        return String(format: "%.2fs", value)
    }
}

struct BackendLatencyPercentiles: Equatable {
    let p50: TimeInterval
    let p95: TimeInterval

    var summary: String {
        "\(BackendLatencyMetrics.format(p50))/\(BackendLatencyMetrics.format(p95))"
    }
}

struct BackendLatencyAggregate: Equatable {
    let backend: STTBackend
    let sampleCount: Int
    let timeToFirstPartial: BackendLatencyPercentiles?
    let stopToFinal: BackendLatencyPercentiles?
    let total: BackendLatencyPercentiles

    var summaryLine: String {
        var parts: [String] = []
        if let timeToFirstPartial {
            parts.append("TTFP \(timeToFirstPartial.summary)")
        }
        if let stopToFinal {
            parts.append("Stop->Final \(stopToFinal.summary)")
        }
        parts.append("Total \(total.summary)")
        return "\(backend.rawValue) [n=\(sampleCount)]: " + parts.joined(separator: ", ")
    }
}
