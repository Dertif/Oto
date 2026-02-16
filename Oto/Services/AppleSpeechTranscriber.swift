import AVFoundation
import Foundation
import Speech

enum AppleSpeechTranscriberError: LocalizedError {
    case recognizerUnavailable
    case speechPermissionDenied
    case unableToAccessInputNode

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the current locale."
        case .speechPermissionDenied:
            return "Speech recognition permission was denied."
        case .unableToAccessInputNode:
            return "Unable to access the microphone input node."
        }
    }
}

final class AppleSpeechTranscriber {
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStopping = false
    private var hasReceivedAnyText = false

    var isRunning: Bool { audioEngine.isRunning }

    func start(
        onUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void
    ) async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw AppleSpeechTranscriberError.recognizerUnavailable
        }

        let authorization = await requestSpeechAuthorization()
        guard authorization == .authorized else {
            throw AppleSpeechTranscriberError.speechPermissionDenied
        }

        stop()
        isStopping = false
        hasReceivedAnyText = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else {
                return
            }
            if let result {
                let text = result.bestTranscription.formattedString
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.hasReceivedAnyText = true
                }
                onUpdate(text, result.isFinal)
            }
            if let error {
                if self.shouldSuppress(error: error) {
                    return
                }
                onError(error.localizedDescription)
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        isStopping = true
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func shouldSuppress(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        if isStopping, hasReceivedAnyText {
            if message.contains("no speech detected") {
                return true
            }
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                return true
            }
        }
        return false
    }

    func currentSpeechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
