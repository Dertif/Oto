import CoreML
import Foundation
import WhisperKit

enum WhisperKitTranscriberError: LocalizedError {
    case missingBundledModelFolder
    case emptyTranscription
    case streamingNotAvailable

    var errorDescription: String? {
        switch self {
        case .missingBundledModelFolder:
            return "Bundled WhisperKit base model was not found. Add model files to Oto/Resources/WhisperModels, or (Debug only) set OTO_ALLOW_WHISPER_DOWNLOAD=1."
        case .emptyTranscription:
            return "WhisperKit returned an empty transcription."
        case .streamingNotAvailable:
            return "WhisperKit streaming could not start for this runtime configuration."
        }
    }
}

enum WhisperModelStatus: String {
    case bundled = "Bundled"
    case downloaded = "Downloaded"
    case missing = "Missing"
}

enum WhisperRuntimeStatus {
    case idle
    case loading
    case prewarming
    case ready
    case streaming
    case finalizing
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
        case .prewarming:
            return "Prewarming"
        case .ready:
            return "Ready"
        case .streaming:
            return "Streaming"
        case .finalizing:
            return "Finalizing"
        case let .error(message):
            return "Error: \(message)"
        }
    }
}

struct WhisperPartialTranscript: Equatable {
    let stableText: String
    let liveText: String

    static let empty = WhisperPartialTranscript(stableText: "", liveText: "")

    var combinedText: String {
        [stableText, liveText]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WhisperQualityTuning: Equatable {
    let requiredSegmentsForConfirmation: Int
    let concurrentWorkerCount: Int
    let useVAD: Bool
}

private struct WhisperDebugOptions {
    let disableStreaming: Bool
    let disablePrewarm: Bool
    let disableComputeTuning: Bool

    static let current = WhisperDebugOptions(
        disableStreaming: envFlag("OTO_DISABLE_WHISPER_STREAMING"),
        disablePrewarm: envFlag("OTO_DISABLE_WHISPER_PREWARM"),
        disableComputeTuning: envFlag("OTO_DISABLE_WHISPER_COMPUTE_TUNING")
    )

    private static func envFlag(_ key: String) -> Bool {
        let rawValue = ProcessInfo.processInfo.environment[key]?.lowercased()
        return rawValue == "1" || rawValue == "true" || rawValue == "yes"
    }
}

final class WhisperKitTranscriber {
    private let fixedModel = "base"
    private let debugOptions = WhisperDebugOptions.current

    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var latestStreamingPartial = WhisperPartialTranscript.empty

    private var hasPrewarmed = false

    private(set) var modelStatus: WhisperModelStatus = .missing
    private(set) var qualityPreset: DictationQualityPreset = .fast
    private(set) var runtimeStatus: WhisperRuntimeStatus = .idle {
        didSet {
            onRuntimeStatusChange?(runtimeStatus)
            if runtimeStatus.label != oldValue.label {
                OtoLogger.log("Runtime status -> \(runtimeStatus.label)", category: .whisper, level: .info)
            }
        }
    }
    var onRuntimeStatusChange: ((WhisperRuntimeStatus) -> Void)?

    var streamingEnabled: Bool {
        !debugOptions.disableStreaming
    }

    var runtimeStatusLabel: String {
        runtimeStatus.label
    }

    func setQualityPreset(_ preset: DictationQualityPreset) {
        qualityPreset = preset
        OtoLogger.log("Whisper quality preset set to \(preset.rawValue)", category: .whisper, level: .info)
    }

    init() {
        modelStatus = detectModelStatus()
        OtoLogger.log(
            "Whisper transcriber initialized (modelStatus=\(modelStatus.rawValue), streaming=\(streamingEnabled ? "enabled" : "disabled"))",
            category: .whisper,
            level: .info
        )
    }

    func prepareForLaunch() async {
        guard !debugOptions.disablePrewarm else {
            runtimeStatus = .idle
            return
        }

        do {
            let runtime = try await loadIfNeeded()
            guard !hasPrewarmed else {
                runtimeStatus = .ready
                return
            }

            runtimeStatus = .prewarming
            try await runtime.prewarmModels()
            hasPrewarmed = true
            runtimeStatus = .ready
        } catch {
            runtimeStatus = .error(error.localizedDescription)
            OtoLogger.log("Prewarm failed: \(error.localizedDescription)", category: .whisper, level: .error)
        }
    }

    func startStreaming(onPartial: @escaping (WhisperPartialTranscript) -> Void) async throws {
        guard streamingEnabled else {
            throw WhisperKitTranscriberError.streamingNotAvailable
        }

        let whisperKit = try await loadIfNeeded()
        guard let tokenizer = whisperKit.tokenizer else {
            throw WhisperKitTranscriberError.streamingNotAvailable
        }

        latestStreamingPartial = .empty

        let tuning = Self.qualityTuning(for: qualityPreset)
        let decodeOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            withoutTimestamps: true,
            wordTimestamps: false,
            concurrentWorkerCount: tuning.concurrentWorkerCount
        )

        let streamTranscriber = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: decodeOptions,
            requiredSegmentsForConfirmation: tuning.requiredSegmentsForConfirmation,
            useVAD: tuning.useVAD,
            stateChangeCallback: { [weak self] _, newState in
                guard let self else {
                    return
                }

                let partial = Self.buildPartial(from: newState)
                self.latestStreamingPartial = partial
                onPartial(partial)
            }
        )

        self.streamTranscriber = streamTranscriber
        runtimeStatus = .streaming

        streamTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await streamTranscriber.startStreamTranscription()
            } catch {
                self.runtimeStatus = .error(error.localizedDescription)
                OtoLogger.log("Streaming failed: \(error.localizedDescription)", category: .whisper, level: .error)
            }
        }
    }

    func stopStreamingAndFinalize() async throws -> String {
        guard let streamTranscriber else {
            throw WhisperKitTranscriberError.streamingNotAvailable
        }

        runtimeStatus = .finalizing

        await streamTranscriber.stopStreamTranscription()
        let bufferedFallbackAudio = whisperKit.map { Array($0.audioProcessor.audioSamples) } ?? []
        streamTask?.cancel()
        streamTask = nil
        self.streamTranscriber = nil
        
        // Give the stream callback path a short window to publish the final partial.
        var finalText = ""
        for _ in 0..<8 {
            finalText = latestStreamingPartial.combinedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        latestStreamingPartial = .empty

        if finalText.isEmpty {
            // Fallback for short utterances where stream callbacks never emit text.
            OtoLogger.log("Streaming final text empty; trying buffered fallback", category: .whisper, level: .info)
            finalText = try await transcribeBufferedAudioSamples(bufferedFallbackAudio)
        }

        guard !finalText.isEmpty else {
            runtimeStatus = .ready
            throw WhisperKitTranscriberError.emptyTranscription
        }
        runtimeStatus = .ready
        return finalText
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        runtimeStatus = .finalizing
        let whisperKit = try await loadIfNeeded()

        let decodeOptions = DecodingOptions(
            verbose: false,
            withoutTimestamps: true,
            wordTimestamps: false
        )

        let results = try await whisperKit.transcribe(
            audioPath: audioFileURL.path,
            decodeOptions: decodeOptions
        )

        let text = results
            .map(\.text)
            .joined(separator: " ")
        let cleanedText = Self.sanitizeTranscriptionText(text)

        guard !cleanedText.isEmpty else {
            runtimeStatus = .ready
            throw WhisperKitTranscriberError.emptyTranscription
        }

        runtimeStatus = .ready
        return cleanedText
    }

    @discardableResult
    func refreshModelStatus() -> WhisperModelStatus {
        let status = detectModelStatus()
        modelStatus = status
        return status
    }

    private func loadIfNeeded() async throws -> WhisperKit {
        if let whisperKit {
            if hasPrewarmed {
                runtimeStatus = .ready
            }
            return whisperKit
        }

        runtimeStatus = .loading

        if let modelFolderURL = bundledModelFolderURL() {
            let runtime = try await loadRuntime(
                modelFolderURL: modelFolderURL,
                downloadBaseURL: nil,
                download: false,
                preferredCompute: !debugOptions.disableComputeTuning
            )
            whisperKit = runtime
            modelStatus = .bundled
            runtimeStatus = .ready
            return runtime
        }

        if let modelFolderURL = downloadedModelFolderURL() {
            let runtime = try await loadRuntime(
                modelFolderURL: modelFolderURL,
                downloadBaseURL: nil,
                download: false,
                preferredCompute: !debugOptions.disableComputeTuning
            )
            whisperKit = runtime
            modelStatus = .downloaded
            runtimeStatus = .ready
            return runtime
        }

        guard allowDebugModelDownload else {
            modelStatus = .missing
            runtimeStatus = .error(WhisperKitTranscriberError.missingBundledModelFolder.localizedDescription)
            throw WhisperKitTranscriberError.missingBundledModelFolder
        }

        guard let downloadBaseURL = downloadBaseURL(createIfNeeded: true) else {
            modelStatus = .missing
            runtimeStatus = .error(WhisperKitTranscriberError.missingBundledModelFolder.localizedDescription)
            throw WhisperKitTranscriberError.missingBundledModelFolder
        }

        let runtime = try await loadRuntime(
            modelFolderURL: nil,
            downloadBaseURL: downloadBaseURL,
            download: true,
            preferredCompute: !debugOptions.disableComputeTuning
        )
        whisperKit = runtime
        modelStatus = .downloaded
        runtimeStatus = .ready
        return runtime
    }

    private func loadRuntime(
        modelFolderURL: URL?,
        downloadBaseURL: URL?,
        download: Bool,
        preferredCompute: Bool
    ) async throws -> WhisperKit {
        do {
            return try await createRuntime(
                modelFolderURL: modelFolderURL,
                downloadBaseURL: downloadBaseURL,
                download: download,
                computeOptions: preferredCompute ? computeOptions : nil
            )
        } catch {
            guard preferredCompute else {
                throw error
            }

            return try await createRuntime(
                modelFolderURL: modelFolderURL,
                downloadBaseURL: downloadBaseURL,
                download: download,
                computeOptions: nil
            )
        }
    }

    private func createRuntime(
        modelFolderURL: URL?,
        downloadBaseURL: URL?,
        download: Bool,
        computeOptions: ModelComputeOptions?
    ) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: fixedModel,
            downloadBase: downloadBaseURL,
            modelFolder: modelFolderURL?.path,
            computeOptions: computeOptions,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: download
        )

        return try await WhisperKit(config)
    }

    private var computeOptions: ModelComputeOptions {
        let audioEncoderCompute: MLComputeUnits
        if #available(macOS 14.0, iOS 17.0, *) {
            audioEncoderCompute = .cpuAndNeuralEngine
        } else {
            audioEncoderCompute = .cpuAndGPU
        }

        return ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: audioEncoderCompute,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuOnly
        )
    }

    private var allowDebugModelDownload: Bool {
        #if DEBUG
        let rawValue = ProcessInfo.processInfo.environment["OTO_ALLOW_WHISPER_DOWNLOAD"]?.lowercased()
        return rawValue == "1" || rawValue == "true" || rawValue == "yes"
        #else
        return false
        #endif
    }

    private func detectModelStatus() -> WhisperModelStatus {
        if bundledModelFolderURL() != nil {
            return .bundled
        }
        if downloadedModelFolderURL() != nil {
            return .downloaded
        }
        return .missing
    }

    private func downloadedModelFolderURL() -> URL? {
        guard let downloadBaseURL = downloadBaseURL(createIfNeeded: false) else {
            return nil
        }
        return findBundledModelFolder(in: downloadBaseURL)
    }

    private func downloadBaseURL(createIfNeeded: Bool) -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let downloadBaseURL = appSupport.appendingPathComponent("Oto/WhisperKit", isDirectory: true)

        if createIfNeeded {
            do {
                try FileManager.default.createDirectory(at: downloadBaseURL, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }

        return downloadBaseURL
    }

    private func bundledModelFolderURL() -> URL? {
        var candidateRoots: [URL] = []
        if let whisperModelsURL = Bundle.main.url(forResource: "WhisperModels", withExtension: nil) {
            candidateRoots.append(whisperModelsURL)
        }
        if let resourceRootURL = Bundle.main.resourceURL {
            candidateRoots.append(resourceRootURL)
        }

        for root in candidateRoots {
            if let found = findBundledModelFolder(in: root) {
                return found
            }
        }

        return nil
    }

    private func findBundledModelFolder(in rootURL: URL) -> URL? {
        if isValidModelFolder(rootURL) {
            return rootURL
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard isDirectory(url), isValidModelFolder(url) else { continue }
            return url
        }

        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func isValidModelFolder(_ folderURL: URL) -> Bool {
        let hasCoreModels =
            hasModel(named: "MelSpectrogram", in: folderURL) &&
            hasModel(named: "AudioEncoder", in: folderURL) &&
            hasModel(named: "TextDecoder", in: folderURL)

        guard hasCoreModels else {
            return false
        }

        let hasTokenizerArtifacts = hasTokenizerArtifacts(in: folderURL)

        return hasTokenizerArtifacts
    }

    private func hasTokenizerArtifacts(in folderURL: URL) -> Bool {
        let directTokenizer = folderURL.appendingPathComponent("tokenizer.json").path
        let directVocab = folderURL.appendingPathComponent("vocab.json").path
        if FileManager.default.fileExists(atPath: directTokenizer) || FileManager.default.fileExists(atPath: directVocab) {
            return true
        }

        // Supports split Hugging Face + CoreML layouts:
        // .../argmaxinc/whisperkit-coreml/openai_whisper-base (CoreML files)
        // .../openai/whisper-base (tokenizer files)
        let derivedOpenAIPath = folderURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("openai/whisper-base", isDirectory: true)

        let sharedTokenizer = derivedOpenAIPath.appendingPathComponent("tokenizer.json").path
        let sharedVocab = derivedOpenAIPath.appendingPathComponent("vocab.json").path
        return FileManager.default.fileExists(atPath: sharedTokenizer) ||
            FileManager.default.fileExists(atPath: sharedVocab)
    }

    private func hasModel(named modelName: String, in folderURL: URL) -> Bool {
        let compiled = folderURL.appendingPathComponent("\(modelName).mlmodelc").path
        let package = folderURL
            .appendingPathComponent("\(modelName).mlpackage")
            .appendingPathComponent("Data/com.apple.CoreML/model.mlmodel")
            .path

        return FileManager.default.fileExists(atPath: compiled) || FileManager.default.fileExists(atPath: package)
    }

    private static func buildPartial(from state: AudioStreamTranscriber.State) -> WhisperPartialTranscript {
        let stable = normalizedText(from: state.confirmedSegments.map(\.text).joined(separator: " "))

        let liveFromSegments = normalizedText(from: state.unconfirmedSegments.map(\.text).joined(separator: " "))
        let fallbackLive = state.currentText == "Waiting for speech..."
            ? ""
            : normalizedText(from: state.currentText)

        let live = liveFromSegments.isEmpty ? fallbackLive : liveFromSegments

        return WhisperPartialTranscript(stableText: stable, liveText: live)
    }

    private static func normalizedText(from text: String) -> String {
        sanitizeTranscriptionText(text)
    }

    static func sanitizeTranscriptionText(_ rawText: String) -> String {
        TranscriptNormalizer.shared.normalize(rawText)
    }

    static func qualityTuning(for preset: DictationQualityPreset) -> WhisperQualityTuning {
        switch preset {
        case .fast:
            return WhisperQualityTuning(
                requiredSegmentsForConfirmation: 1,
                concurrentWorkerCount: 4,
                useVAD: false
            )
        case .accurate:
            return WhisperQualityTuning(
                requiredSegmentsForConfirmation: 2,
                concurrentWorkerCount: 2,
                useVAD: true
            )
        }
    }

    private func transcribeBufferedAudioSamples(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty, let whisperKit else {
            return ""
        }

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(
                verbose: false,
                withoutTimestamps: true,
                wordTimestamps: false
            )
        )

        let text = results
            .map(\.text)
            .joined(separator: " ")
        return Self.sanitizeTranscriptionText(text)
    }
}
