import Foundation

struct TextRefinementRequest: Equatable {
    let backend: STTBackend
    let mode: TextRefinementMode
    let rawText: String
    let runID: String?
}

struct TextRefinementDiagnostics: Equatable {
    let mode: TextRefinementMode
    let availability: String
    let latency: TimeInterval?
    let fallbackReason: String?
    let outputSource: TextOutputSource
}

struct TextRefinementResult: Equatable {
    let text: String
    let outputSource: TextOutputSource
    let diagnostics: TextRefinementDiagnostics

    static func raw(
        text: String,
        mode: TextRefinementMode,
        availability: String,
        fallbackReason: String? = nil,
        latency: TimeInterval? = nil
    ) -> TextRefinementResult {
        TextRefinementResult(
            text: text,
            outputSource: .raw,
            diagnostics: TextRefinementDiagnostics(
                mode: mode,
                availability: availability,
                latency: latency,
                fallbackReason: fallbackReason,
                outputSource: .raw
            )
        )
    }

    static func refined(
        text: String,
        mode: TextRefinementMode,
        availability: String,
        latency: TimeInterval?
    ) -> TextRefinementResult {
        TextRefinementResult(
            text: text,
            outputSource: .refined,
            diagnostics: TextRefinementDiagnostics(
                mode: mode,
                availability: availability,
                latency: latency,
                fallbackReason: nil,
                outputSource: .refined
            )
        )
    }
}
