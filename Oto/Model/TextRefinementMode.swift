import Foundation

enum TextRefinementMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case enhanced = "Enhanced"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .raw:
            return "Use normalized transcript text without LLM refinement."
        case .enhanced:
            return "Apply on-device refinement for readability while preserving meaning."
        }
    }
}

enum TextOutputSource: String, Equatable {
    case raw
    case refined
}
