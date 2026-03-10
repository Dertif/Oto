import XCTest
@testable import Oto

@MainActor
final class AudioFileTranscriptionServiceTests: XCTestCase {
    private final class AppleSpeechMock: AppleSpeechAudioFileTranscribing {
        let text: String

        init(text: String) {
            self.text = text
        }

        func transcribe(audioFileURL: URL) async throws -> String {
            text
        }
    }

    private final class WhisperKitMock: WhisperKitAudioFileTranscribing {
        let text: String
        private(set) var receivedPresets: [DictationQualityPreset] = []

        init(text: String) {
            self.text = text
        }

        func setQualityPreset(_ preset: DictationQualityPreset) {
            receivedPresets.append(preset)
        }

        func transcribe(audioFileURL: URL) async throws -> String {
            text
        }
    }

    private final class WhisperCppMock: WhisperCppAudioFileTranscribing {
        let text: String
        private(set) var selectedModels: [WhisperCppModel] = []

        init(text: String) {
            self.text = text
        }

        func selectModel(_ model: WhisperCppModel) {
            selectedModels.append(model)
        }

        func transcribe(audioFileURL: URL) async throws -> String {
            text
        }
    }

    func testAppleSpeechTranscriptionIsNormalized() async throws {
        let service = AudioFileTranscriptionService(
            appleSpeechTranscriber: AppleSpeechMock(text: "Hello   world ."),
            whisperKitTranscriber: WhisperKitMock(text: ""),
            whisperCppTranscriber: WhisperCppMock(text: "")
        )

        let result = try await service.transcribe(
            audioFileURL: URL(fileURLWithPath: "/tmp/sample.m4a"),
            model: .appleSpeech
        )

        XCTAssertEqual(result.backend, .appleSpeech)
        XCTAssertEqual(result.model, .appleSpeech)
        XCTAssertNil(result.qualityPreset)
        XCTAssertEqual(result.text, "Hello world.")
    }

    func testWhisperKitTranscriptionUsesRequestedPreset() async throws {
        let whisperKit = WhisperKitMock(text: "<|startoftranscript|> hello   world")
        let service = AudioFileTranscriptionService(
            appleSpeechTranscriber: AppleSpeechMock(text: ""),
            whisperKitTranscriber: whisperKit,
            whisperCppTranscriber: WhisperCppMock(text: "")
        )

        let result = try await service.transcribe(
            audioFileURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            model: .whisperKitBase,
            qualityPreset: .accurate
        )

        XCTAssertEqual(result.backend, .whisper)
        XCTAssertEqual(result.model, .whisperKitBase)
        XCTAssertEqual(result.qualityPreset, .accurate)
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(whisperKit.receivedPresets, [.accurate])
    }

    func testWhisperCppTranscriptionSelectsRequestedModel() async throws {
        let whisperCpp = WhisperCppMock(text: "  bonjour   monde  ")
        let service = AudioFileTranscriptionService(
            appleSpeechTranscriber: AppleSpeechMock(text: ""),
            whisperKitTranscriber: WhisperKitMock(text: ""),
            whisperCppTranscriber: whisperCpp
        )

        let result = try await service.transcribe(
            audioFileURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            model: .whisperCpp(.base)
        )

        XCTAssertEqual(result.backend, .whisperCpp)
        XCTAssertEqual(result.model, .whisperCpp(.base))
        XCTAssertNil(result.qualityPreset)
        XCTAssertEqual(result.text, "bonjour monde")
        XCTAssertEqual(whisperCpp.selectedModels, [.base])
    }
}
