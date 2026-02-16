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
    let failureContextURL: URL?
    let whisperLatencySummary: String
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
        let isProcessing = snapshot.phase == .transcribing || snapshot.phase == .injecting

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
            failureContextURL: snapshot.artifacts.failureContextURL,
            whisperLatencySummary: snapshot.whisperLatencySummary
        )
    }
}
