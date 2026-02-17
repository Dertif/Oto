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

enum AppleSpeechTerminalErrorClass: Equatable {
    case usableFinal
    case expectedStopNoise
    case realFailure
}

@MainActor
final class AppleSpeechTranscriber {
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStopping = false
    private var hasReceivedAnyText = false
    private var hasFinalResult = false
    private var latestTranscript = ""
    private var finalizationWaiter: CheckedContinuation<Void, Never>?

    var isRunning: Bool { audioEngine.isRunning }

    func start(
        onUpdate: @escaping (String, Bool) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
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
        hasFinalResult = false
        latestTranscript = ""
        finalizationWaiter = nil

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.hasReceivedAnyText = true
                        self.latestTranscript = text
                    }
                    if result.isFinal {
                        self.hasFinalResult = true
                        self.resumeFinalizationWaiter()
                    }
                    onUpdate(text, result.isFinal)
                }

                if let error {
                    let classification = Self.classifyTerminalError(
                        error: error as NSError,
                        isStopping: self.isStopping,
                        hasUsableTranscript: self.hasReceivedAnyText || self.hasFinalResult,
                        hasFinalResult: self.hasFinalResult
                    )

                    if classification != .realFailure {
                        self.resumeFinalizationWaiter()
                        return
                    }

                    if self.isStopping {
                        self.resumeFinalizationWaiter()
                    }
                    onError(error.localizedDescription)
                }
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            onAudioLevel(Self.normalizedAudioLevel(from: buffer))
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
        hasFinalResult = false
        finalizationWaiter = nil

        endAudioInput()
        cleanupRecognition()
    }

    func stopAndFinalize(timeout: TimeInterval = 0.75) async -> String {
        isStopping = true
        endAudioInput()

        if recognitionTask != nil, !hasFinalResult {
            await waitForFinalResult(timeout: timeout)
        }

        let finalText = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupRecognition()
        return finalText
    }

    private func endAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func cleanupRecognition() {
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func waitForFinalResult(timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.finalizationWaiter = continuation

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.resumeFinalizationWaiter()
                }
            }
        }
    }

    private func resumeFinalizationWaiter() {
        guard let finalizationWaiter else {
            return
        }
        self.finalizationWaiter = nil
        finalizationWaiter.resume()
    }

    static func classifyTerminalError(
        error: NSError,
        isStopping: Bool,
        hasUsableTranscript: Bool,
        hasFinalResult: Bool
    ) -> AppleSpeechTerminalErrorClass {
        if isStopping, hasUsableTranscript {
            return .expectedStopNoise
        }

        if hasFinalResult {
            return .usableFinal
        }

        let message = error.localizedDescription.lowercased()
        if isStopping, message.contains("no speech detected") {
            return .expectedStopNoise
        }

        return .realFailure
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

    private static func normalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard
            buffer.frameLength > 0,
            let channelData = buffer.floatChannelData
        else {
            return 0
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        var sumSquares: Float = 0

        for channel in 0 ..< channelCount {
            let samples = channelData[channel]
            for index in 0 ..< frameCount {
                let sample = samples[index]
                sumSquares += sample * sample
            }
        }

        let meanSquare = sumSquares / Float(frameCount * channelCount)
        guard meanSquare > 0 else {
            return 0
        }

        let rms = sqrt(meanSquare)
        let db = 20 * log10(rms)
        let normalized = (db + 52) / 52
        return min(1, max(0, normalized))
    }
}
