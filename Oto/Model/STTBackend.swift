import Foundation

enum STTBackend: String, CaseIterable, Identifiable {
    case appleSpeech = "Apple Speech"
    case whisper = "WhisperKit"

    var id: String { rawValue }

    var fileSlug: String {
        switch self {
        case .appleSpeech:
            return "apple-speech"
        case .whisper:
            return "whisper"
        }
    }
}
