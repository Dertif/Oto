import Foundation

struct WhisperLatencyMetrics: Equatable {
    let usedStreaming: Bool
    let timeToFirstPartial: TimeInterval?
    let stopToFinalTranscript: TimeInterval?
    let totalDuration: TimeInterval

    var summary: String {
        let modeLabel = usedStreaming ? "streaming" : "file"
        let ttfpLabel = format(timeToFirstPartial)
        let stopToFinalLabel = format(stopToFinalTranscript)
        let totalLabel = format(totalDuration)

        return "Whisper latency (\(modeLabel)) - TTFP: \(ttfpLabel), Stop->Final: \(stopToFinalLabel), Total: \(totalLabel)"
    }

    private func format(_ value: TimeInterval?) -> String {
        guard let value else {
            return "n/a"
        }
        return String(format: "%.2fs", value)
    }
}

final class WhisperLatencyTracker {
    private var runStartedAt: Date?
    private var firstPartialAt: Date?
    private var stopRequestedAt: Date?
    private var usedStreaming = false

    func beginRun(usingStreaming: Bool, at date: Date = Date()) {
        runStartedAt = date
        firstPartialAt = nil
        stopRequestedAt = nil
        self.usedStreaming = usingStreaming
    }

    func markFirstPartial(at date: Date = Date()) {
        guard runStartedAt != nil, firstPartialAt == nil else {
            return
        }
        firstPartialAt = date
    }

    func markStopRequested(at date: Date = Date()) {
        guard runStartedAt != nil, stopRequestedAt == nil else {
            return
        }
        stopRequestedAt = date
    }

    func finish(at date: Date = Date()) -> WhisperLatencyMetrics? {
        guard let runStartedAt else {
            return nil
        }

        let metrics = WhisperLatencyMetrics(
            usedStreaming: usedStreaming,
            timeToFirstPartial: firstPartialAt.map { $0.timeIntervalSince(runStartedAt) },
            stopToFinalTranscript: stopRequestedAt.map { date.timeIntervalSince($0) },
            totalDuration: date.timeIntervalSince(runStartedAt)
        )
        reset()
        return metrics
    }

    func reset() {
        runStartedAt = nil
        firstPartialAt = nil
        stopRequestedAt = nil
        usedStreaming = false
    }
}
