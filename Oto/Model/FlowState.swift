import Foundation

enum FlowPhase: Equatable {
    case idle
    case listening
    case transcribing
    case refining
    case injecting
    case completed
    case failed
}

struct FlowSnapshot: Equatable {
    var phase: FlowPhase = .idle
    var runID: String?
    var activeBackend: STTBackend?
    var statusMessage: String = "Ready"
    var recordingAudioLevel: Float = 0
    var transcriptStableText: String = ""
    var transcriptLiveText: String = ""
    var rawTranscriptText: String = ""
    var refinedTranscriptText: String = ""
    var finalTranscriptText: String = ""
    var outputSource: TextOutputSource?
    var refinementDiagnostics: TextRefinementDiagnostics?
    var artifacts: TranscriptArtifacts = .empty
    var latencySummary: String = "Latency P50/P95: no runs yet."
    var refinementLatencySummary: String = "Refinement P50/P95: no runs yet."
    var lastEvent: FlowEvent?
    var failureMessage: String?

    static let initial = FlowSnapshot()
}
