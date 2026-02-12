import Foundation
import WhisperKit

enum WhisperKitTranscriberError: LocalizedError {
    case missingBundledModelFolder
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .missingBundledModelFolder:
            return "Bundled WhisperKit base model was not found. Add model files to Oto/Resources/WhisperModels, or (Debug only) set OTO_ALLOW_WHISPER_DOWNLOAD=1."
        case .emptyTranscription:
            return "WhisperKit returned an empty transcription."
        }
    }
}

enum WhisperModelStatus: String {
    case bundled = "Bundled"
    case downloaded = "Downloaded"
    case missing = "Missing"
}

final class WhisperKitTranscriber {
    private let fixedModel = "base"
    private var whisperKit: WhisperKit?
    private(set) var modelStatus: WhisperModelStatus = .missing

    init() {
        modelStatus = detectModelStatus()
    }

    func transcribe(audioFileURL: URL) async throws -> String {
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
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw WhisperKitTranscriberError.emptyTranscription
        }

        return text
    }

    @discardableResult
    func refreshModelStatus() -> WhisperModelStatus {
        let status = detectModelStatus()
        modelStatus = status
        return status
    }

    private func loadIfNeeded() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        if let modelFolderURL = bundledModelFolderURL() {
            let config = WhisperKitConfig(
                model: fixedModel,
                modelFolder: modelFolderURL.path,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )
            let whisperKit = try await WhisperKit(config)
            self.whisperKit = whisperKit
            modelStatus = .bundled
            return whisperKit
        }

        if let modelFolderURL = downloadedModelFolderURL() {
            let config = WhisperKitConfig(
                model: fixedModel,
                modelFolder: modelFolderURL.path,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )
            let whisperKit = try await WhisperKit(config)
            self.whisperKit = whisperKit
            modelStatus = .downloaded
            return whisperKit
        }

        guard allowDebugModelDownload else {
            modelStatus = .missing
            throw WhisperKitTranscriberError.missingBundledModelFolder
        }

        guard let downloadBaseURL = downloadBaseURL(createIfNeeded: true) else {
            modelStatus = .missing
            throw WhisperKitTranscriberError.missingBundledModelFolder
        }

        let config = WhisperKitConfig(
            model: fixedModel,
            downloadBase: downloadBaseURL,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: true
        )

        let whisperKit = try await WhisperKit(config)
        self.whisperKit = whisperKit
        modelStatus = .downloaded
        return whisperKit
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
}
