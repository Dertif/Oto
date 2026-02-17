import Foundation

enum DictationQualityPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case accurate = "Accurate"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .fast:
            return "Lower latency, more responsive partials."
        case .accurate:
            return "More stable confirmations with higher final quality."
        }
    }
}
