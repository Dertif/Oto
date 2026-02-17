import Foundation

enum FlowEvent: Equatable {
    case startRequested(backend: STTBackend, message: String)
    case stopRequested(message: String)
    case transcriptionProgress(stable: String, live: String)
    case captureTooShort(message: String)
    case captureFailed(message: String)
    case transcriptionSucceeded(text: String)
    case refinementStarted(message: String)
    case refinementSucceeded(text: String, diagnostics: TextRefinementDiagnostics)
    case refinementSkipped(text: String, message: String, diagnostics: TextRefinementDiagnostics)
    case refinementFailedFallback(text: String, message: String, diagnostics: TextRefinementDiagnostics)
    case transcriptionFailed(message: String)
    case injectionStarted
    case injectionSucceeded(message: String)
    case injectionSkipped(message: String)
    case injectionFailed(message: String)
    case resetToIdle(message: String)
}
