import Foundation

@MainActor
protocol AppleSpeechAudioFileTranscribing: AnyObject {
    func transcribe(audioFileURL: URL) async throws -> String
}

@MainActor
protocol WhisperKitAudioFileTranscribing: AnyObject {
    func setQualityPreset(_ preset: DictationQualityPreset)
    func transcribe(audioFileURL: URL) async throws -> String
}

@MainActor
protocol WhisperCppAudioFileTranscribing: AnyObject {
    func selectModel(_ model: WhisperCppModel)
    func transcribe(audioFileURL: URL) async throws -> String
}

enum AudioFileTranscriptionModel: Equatable {
    case appleSpeech
    case whisperKitBase
    case whisperCpp(WhisperCppModel)

    var backend: STTBackend {
        switch self {
        case .appleSpeech:
            return .appleSpeech
        case .whisperKitBase:
            return .whisper
        case .whisperCpp:
            return .whisperCpp
        }
    }

    var cliValue: String {
        switch self {
        case .appleSpeech:
            return "apple-speech"
        case .whisperKitBase:
            return "whisper-base"
        case let .whisperCpp(model):
            return model.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .whisperKitBase:
            return "WhisperKit base"
        case let .whisperCpp(model):
            return "Whisper.cpp \(model.displayName)"
        }
    }

    var supportsQualityPreset: Bool {
        if case .whisperKitBase = self {
            return true
        }
        return false
    }

    static func parse(_ rawValue: String) -> AudioFileTranscriptionModel? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "apple", "apple-speech", "speech":
            return .appleSpeech
        case "whisper", "whisper-base", "whisperkit", "whisperkit-base":
            return .whisperKitBase
        default:
            break
        }

        let whisperCppRawValue = normalized
            .replacingOccurrences(of: "whisper-cpp:", with: "")
            .replacingOccurrences(of: "whispercpp:", with: "")
            .replacingOccurrences(of: "whisper-cpp/", with: "")
            .replacingOccurrences(of: "whispercpp/", with: "")
        guard let model = WhisperCppModel(rawValue: whisperCppRawValue) else {
            return nil
        }
        return .whisperCpp(model)
    }
}

struct AudioFileTranscriptionResult: Equatable {
    let text: String
    let backend: STTBackend
    let model: AudioFileTranscriptionModel
    let qualityPreset: DictationQualityPreset?
}

enum AudioFileTranscriptionServiceError: LocalizedError {
    case emptyTranscription(model: AudioFileTranscriptionModel)

    var errorDescription: String? {
        switch self {
        case let .emptyTranscription(model):
            return "\(model.displayName) returned an empty transcription."
        }
    }
}

@MainActor
final class AudioFileTranscriptionService {
    private let appleSpeechTranscriber: AppleSpeechAudioFileTranscribing
    private let whisperKitTranscriber: WhisperKitAudioFileTranscribing
    private let whisperCppTranscriber: WhisperCppAudioFileTranscribing
    private let transcriptNormalizer: TranscriptNormalizer

    init(
        appleSpeechTranscriber: AppleSpeechAudioFileTranscribing? = nil,
        whisperKitTranscriber: WhisperKitAudioFileTranscribing? = nil,
        whisperCppTranscriber: WhisperCppAudioFileTranscribing? = nil,
        transcriptNormalizer: TranscriptNormalizer = .shared
    ) {
        self.appleSpeechTranscriber = appleSpeechTranscriber ?? AppleSpeechTranscriber()
        self.whisperKitTranscriber = whisperKitTranscriber ?? WhisperKitTranscriber()
        self.whisperCppTranscriber = whisperCppTranscriber ?? WhisperCppTranscriber()
        self.transcriptNormalizer = transcriptNormalizer
    }

    func transcribe(
        audioFileURL: URL,
        model: AudioFileTranscriptionModel,
        qualityPreset: DictationQualityPreset = .fast
    ) async throws -> AudioFileTranscriptionResult {
        let text: String
        let resolvedQualityPreset: DictationQualityPreset?

        switch model {
        case .appleSpeech:
            text = try await appleSpeechTranscriber.transcribe(audioFileURL: audioFileURL)
            resolvedQualityPreset = nil
        case .whisperKitBase:
            whisperKitTranscriber.setQualityPreset(qualityPreset)
            text = try await whisperKitTranscriber.transcribe(audioFileURL: audioFileURL)
            resolvedQualityPreset = qualityPreset
        case let .whisperCpp(selectedModel):
            whisperCppTranscriber.selectModel(selectedModel)
            text = try await whisperCppTranscriber.transcribe(audioFileURL: audioFileURL)
            resolvedQualityPreset = nil
        }

        let normalizedText = transcriptNormalizer.normalize(text)
        guard !normalizedText.isEmpty else {
            throw AudioFileTranscriptionServiceError.emptyTranscription(model: model)
        }

        return AudioFileTranscriptionResult(
            text: normalizedText,
            backend: model.backend,
            model: model,
            qualityPreset: resolvedQualityPreset
        )
    }
}

extension AppleSpeechTranscriber: AppleSpeechAudioFileTranscribing {}
extension WhisperKitTranscriber: WhisperKitAudioFileTranscribing {}
extension WhisperCppTranscriber: WhisperCppAudioFileTranscribing {}
