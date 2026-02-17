import Foundation

enum FlowReducerDiagnostics {
#if DEBUG
    static var invalidTransitionHandler: ((String) -> Void)? = { message in
        guard OtoLogger.assertOnInvalidTransition else {
            return
        }
        assertionFailure(message)
    }
#else
    static var invalidTransitionHandler: ((String) -> Void)?
#endif
}

enum FlowReducer {
    static func reduce(snapshot: FlowSnapshot, event: FlowEvent) -> FlowSnapshot {
        var next = snapshot

        func reject(_ reason: String) -> FlowSnapshot {
            let message = "Invalid transition from \(snapshot.phase) with event \(event): \(reason)"
            OtoLogger.log(message, category: .flow, level: .error)
            FlowReducerDiagnostics.invalidTransitionHandler?(message)
            return snapshot
        }

        switch event {
        case let .startRequested(backend, message):
            guard [.idle, .completed, .failed].contains(snapshot.phase) else {
                return reject("startRequested is only valid from idle/completed/failed")
            }
            next.phase = .listening
            next.activeBackend = backend
            next.statusMessage = message
            next.transcriptStableText = ""
            next.transcriptLiveText = ""
            next.rawTranscriptText = ""
            next.refinedTranscriptText = ""
            next.finalTranscriptText = ""
            next.outputSource = nil
            next.refinementDiagnostics = nil
            next.failureMessage = nil

        case let .stopRequested(message):
            guard snapshot.phase == .listening else {
                return reject("stopRequested is only valid from listening")
            }
            next.phase = .transcribing
            next.statusMessage = message

        case let .transcriptionProgress(stable, live):
            guard snapshot.phase == .listening || snapshot.phase == .transcribing else {
                return reject("transcriptionProgress is only valid from listening/transcribing")
            }
            next.transcriptStableText = stable
            next.transcriptLiveText = live

        case let .captureTooShort(message):
            guard snapshot.phase == .listening else {
                return reject("captureTooShort is only valid from listening")
            }
            next.phase = .failed
            next.statusMessage = message
            next.failureMessage = message
            next.activeBackend = nil

        case let .captureFailed(message):
            guard snapshot.phase == .listening || snapshot.phase == .transcribing || snapshot.phase == .refining || snapshot.phase == .injecting else {
                return reject("captureFailed is only valid from listening/transcribing/refining/injecting")
            }
            next.phase = .failed
            next.statusMessage = message
            next.failureMessage = message
            next.activeBackend = nil

        case let .transcriptionSucceeded(text):
            guard snapshot.phase == .transcribing else {
                return reject("transcriptionSucceeded is only valid from transcribing")
            }
            next.phase = .refining
            next.statusMessage = "Refining transcript..."
            next.rawTranscriptText = text
            next.finalTranscriptText = text
            next.transcriptStableText = text
            next.transcriptLiveText = ""
            next.outputSource = .raw

        case let .refinementStarted(message):
            guard snapshot.phase == .refining else {
                return reject("refinementStarted is only valid from refining")
            }
            next.statusMessage = message

        case let .refinementSucceeded(text, diagnostics):
            guard snapshot.phase == .refining else {
                return reject("refinementSucceeded is only valid from refining")
            }
            next.phase = .injecting
            next.statusMessage = "Injecting refined transcript..."
            next.refinedTranscriptText = text
            next.finalTranscriptText = text
            next.transcriptStableText = text
            next.transcriptLiveText = ""
            next.outputSource = .refined
            next.refinementDiagnostics = diagnostics

        case let .refinementSkipped(text, message, diagnostics):
            guard snapshot.phase == .refining else {
                return reject("refinementSkipped is only valid from refining")
            }
            next.phase = .injecting
            next.statusMessage = message
            next.finalTranscriptText = text
            next.transcriptStableText = text
            next.transcriptLiveText = ""
            next.outputSource = .raw
            next.refinementDiagnostics = diagnostics

        case let .refinementFailedFallback(text, message, diagnostics):
            guard snapshot.phase == .refining else {
                return reject("refinementFailedFallback is only valid from refining")
            }
            next.phase = .injecting
            next.statusMessage = message
            next.finalTranscriptText = text
            next.transcriptStableText = text
            next.transcriptLiveText = ""
            next.outputSource = .raw
            next.refinementDiagnostics = diagnostics

        case let .transcriptionFailed(message):
            guard snapshot.phase == .transcribing || snapshot.phase == .refining else {
                return reject("transcriptionFailed is only valid from transcribing/refining")
            }
            next.phase = .failed
            next.statusMessage = message
            next.failureMessage = message
            next.activeBackend = nil

        case .injectionStarted:
            guard snapshot.phase == .injecting else {
                return reject("injectionStarted is only valid from injecting")
            }
            next.statusMessage = "Injecting transcript..."

        case let .injectionSucceeded(message):
            guard snapshot.phase == .injecting else {
                return reject("injectionSucceeded is only valid from injecting")
            }
            next.phase = .completed
            next.statusMessage = message
            next.activeBackend = nil

        case let .injectionSkipped(message):
            guard snapshot.phase == .injecting else {
                return reject("injectionSkipped is only valid from injecting")
            }
            next.phase = .completed
            next.statusMessage = message
            next.activeBackend = nil

        case let .injectionFailed(message):
            guard snapshot.phase == .injecting else {
                return reject("injectionFailed is only valid from injecting")
            }
            next.phase = .failed
            next.statusMessage = message
            next.failureMessage = message
            next.activeBackend = nil

        case let .resetToIdle(message):
            guard [.idle, .completed, .failed].contains(snapshot.phase) else {
                return reject("resetToIdle is only valid from idle/completed/failed")
            }
            next.phase = .idle
            next.activeBackend = nil
            next.statusMessage = message
            next.transcriptLiveText = ""
            next.transcriptStableText = ""
            next.rawTranscriptText = ""
            next.refinedTranscriptText = ""
            next.finalTranscriptText = ""
            next.outputSource = nil
            next.refinementDiagnostics = nil
            next.failureMessage = nil
        }

        next.lastEvent = event
        OtoLogger.flowTrace("Transition \(snapshot.phase) -> \(next.phase) via \(event)")
        return next
    }
}
