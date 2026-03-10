import Foundation

enum WhisperCppModel: String, CaseIterable, Identifiable {
    case tinyEn = "tiny.en"
    case baseEn = "base.en"
    case base = "base"
    case smallEn = "small.en"
    case small = "small"

    var id: String { rawValue }

    var filename: String {
        "ggml-\(rawValue).bin"
    }

    var displayName: String {
        rawValue
    }

    var detailText: String {
        switch self {
        case .tinyEn:
            return "English-only"
        case .baseEn:
            return "English-only"
        case .base:
            return "Multilingual"
        case .smallEn:
            return "English-only"
        case .small:
            return "Multilingual"
        }
    }

    var remoteURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}
