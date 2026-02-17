import Foundation

struct AppUIProjection: Equatable {
    let reliabilityState: ReliabilityFlowState
    let isRecording: Bool
    let isProcessing: Bool
    let visualState: RecorderVisualState
    let statusMessage: String
    let transcriptStableText: String
    let transcriptLiveText: String
    let primaryTranscriptURL: URL?
    let rawTranscriptURL: URL?
    let refinedTranscriptURL: URL?
    let failureContextURL: URL?
    let latencySummary: String
    let refinementLatencySummary: String
    let outputSource: TextOutputSource?
    let refinementDiagnostics: TextRefinementDiagnostics?
}

enum AppStateMapper {
    static func map(snapshot: FlowSnapshot) -> AppUIProjection {
        let reliabilityState: ReliabilityFlowState
        switch snapshot.phase {
        case .idle:
            reliabilityState = .ready
        case .listening:
            reliabilityState = .listening
        case .transcribing:
            reliabilityState = .transcribing
        case .refining:
            reliabilityState = .transcribing
        case .injecting:
            reliabilityState = .transcribing
        case .completed:
            if case .injectionSucceeded = snapshot.lastEvent {
                reliabilityState = .injected
            } else {
                reliabilityState = .ready
            }
        case .failed:
            reliabilityState = .failed
        }

        let isRecording = snapshot.phase == .listening
        let isProcessing = snapshot.phase == .transcribing || snapshot.phase == .refining || snapshot.phase == .injecting

        let visualState: RecorderVisualState
        if isProcessing {
            visualState = .processing
        } else if isRecording {
            visualState = .recording
        } else {
            visualState = .idle
        }

        return AppUIProjection(
            reliabilityState: reliabilityState,
            isRecording: isRecording,
            isProcessing: isProcessing,
            visualState: visualState,
            statusMessage: snapshot.statusMessage,
            transcriptStableText: snapshot.transcriptStableText,
            transcriptLiveText: snapshot.transcriptLiveText,
            primaryTranscriptURL: snapshot.artifacts.primaryURL,
            rawTranscriptURL: snapshot.artifacts.rawURL,
            refinedTranscriptURL: snapshot.artifacts.refinedURL,
            failureContextURL: snapshot.artifacts.failureContextURL,
            latencySummary: snapshot.latencySummary,
            refinementLatencySummary: snapshot.refinementLatencySummary,
            outputSource: snapshot.outputSource,
            refinementDiagnostics: snapshot.refinementDiagnostics
        )
    }
}
