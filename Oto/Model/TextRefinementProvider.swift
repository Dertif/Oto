import Foundation

enum TextRefinementProvider: String, CaseIterable, Identifiable {
    case appleIntelligence = "Apple Intelligence"
    case lmStudio = "LM Studio"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .appleIntelligence:
            return "Use Apple's on-device language model when available."
        case .lmStudio:
            return "Use a local LLM served by LM Studio over localhost."
        }
    }
}
