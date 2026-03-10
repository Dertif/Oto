import Foundation
import whisper

enum WhisperCppTranscriberError: LocalizedError {
    case modelMissing(WhisperCppModel)
    case contextInitializationFailed
    case transcriptionFailed
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case let .modelMissing(model):
            return "Download the \(model.displayName) whisper.cpp model before using this backend."
        case .contextInitializationFailed:
            return "Whisper.cpp could not initialize the selected model."
        case .transcriptionFailed:
            return "Whisper.cpp failed to transcribe the audio file."
        case .emptyTranscription:
            return "Whisper.cpp returned an empty transcription."
        }
    }
}

private enum WhisperCppRuntimeStatus {
    case idle
    case loadingModel
    case ready
    case downloading
    case transcribing
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .loadingModel:
            return "Loading model"
        case .ready:
            return "Ready"
        case .downloading:
            return "Downloading model"
        case .transcribing:
            return "Transcribing"
        case let .error(message):
            return "Error: \(message)"
        }
    }
}

private actor WhisperCppContext {
    private var context: OpaquePointer?
    private var loadedModelPath: String?

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func reset() {
        if let context {
            whisper_free(context)
        }
        context = nil
        loadedModelPath = nil
    }

    func transcribe(samples: [Float], modelPath: String, preferredLanguage: String?) throws -> String {
        let context = try loadContextIfNeeded(modelPath: modelPath)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.n_threads = Int32(Self.threadCount)
        params.offset_ms = 0

        let result: Int32 = if let preferredLanguage {
            preferredLanguage.withCString { language in
                params.language = language
                return samples.withUnsafeBufferPointer { buffer in
                    whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                }
            }
        } else {
            samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
        }

        guard result == 0 else {
            throw WhisperCppTranscriberError.transcriptionFailed
        }

        var transcription = ""
        for index in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, index))
        }

        return TranscriptNormalizer.shared.normalize(transcription)
    }

    private func loadContextIfNeeded(modelPath: String) throws -> OpaquePointer {
        if let context, loadedModelPath == modelPath {
            return context
        }

        reset()

        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperCppTranscriberError.contextInitializationFailed
        }

        self.context = context
        loadedModelPath = modelPath
        return context
    }

    private static var threadCount: Int {
        max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
    }
}

private final class WhisperCppModelDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destinationURL: URL?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var session: URLSession?
    private(set) var downloadTask: URLSessionDownloadTask?

    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        self.destinationURL = destinationURL
        self.progressHandler = progressHandler

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
        self.session = session

        let downloadTask = session.downloadTask(with: sourceURL)
        self.downloadTask = downloadTask
        downloadTask.resume()

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        downloadTask?.cancel()
    }

    private func finish(result: Result<Void, Error>) {
        switch result {
        case .success:
            continuation?.resume()
        case let .failure(error):
            continuation?.resume(throwing: error)
        }

        continuation = nil
        downloadTask = nil
        destinationURL = nil
        progressHandler = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationURL else {
            finish(result: .failure(WhisperCppTranscriberError.transcriptionFailed))
            return
        }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            finish(result: .success(()))
        } catch {
            finish(result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, continuation != nil else {
            return
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            finish(result: .failure(CancellationError()))
            return
        }

        finish(result: .failure(error))
    }
}

@MainActor
final class WhisperCppTranscriber {
    var onStateChange: ((WhisperCppRuntimeSnapshot) -> Void)?

    private let context = WhisperCppContext()
    private let fileManager: FileManager
    private let modelDirectoryURL: URL

    private var runtimeStatus: WhisperCppRuntimeStatus = .idle {
        didSet { emitStateChange() }
    }
    private(set) var selectedModel: WhisperCppModel {
        didSet { emitStateChange() }
    }
    private(set) var downloadState: WhisperCppModelDownloadState = .notDownloaded {
        didSet { emitStateChange() }
    }

    private var activeDownloader: WhisperCppModelDownloader?

    let supportedModels = WhisperCppModel.allCases

    init(
        selectedModel: WhisperCppModel = .baseEn,
        fileManager: FileManager = .default
    ) {
        self.selectedModel = selectedModel
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.modelDirectoryURL = appSupport.appendingPathComponent("Oto/WhisperCppModels", isDirectory: true)
        let snapshot = refreshState()
        OtoLogger.log(
            "Whisper.cpp transcriber initialized (model=\(snapshot.selectedModel.rawValue), status=\(snapshot.modelStatusLabel))",
            category: .whisper,
            level: .info
        )
    }

    var runtimeStatusLabel: String {
        runtimeStatus.label
    }

    var modelStatusLabel: String {
        modelFileExists(for: selectedModel) ? "Available locally" : "Missing"
    }

    func prepareForLaunch() async {
        _ = refreshState()
    }

    @discardableResult
    func refreshState() -> WhisperCppRuntimeSnapshot {
        if activeDownloader == nil {
            downloadState = modelFileExists(for: selectedModel) ? .downloaded : .notDownloaded
            if case .error = runtimeStatus {
                // Preserve explicit runtime errors until the next action.
            } else {
                runtimeStatus = modelFileExists(for: selectedModel) ? .ready : .idle
            }
        }
        return snapshot
    }

    func selectModel(_ model: WhisperCppModel) {
        guard selectedModel != model else {
            _ = refreshState()
            return
        }

        cancelDownload()
        selectedModel = model
        Task {
            await context.reset()
        }
        _ = refreshState()
    }

    func downloadSelectedModel() async {
        guard activeDownloader == nil else {
            return
        }

        do {
            try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        } catch {
            runtimeStatus = .error(error.localizedDescription)
            downloadState = .failed(error.localizedDescription)
            return
        }

        if modelFileExists(for: selectedModel) {
            runtimeStatus = .ready
            downloadState = .downloaded
            return
        }

        let downloader = WhisperCppModelDownloader()
        activeDownloader = downloader
        runtimeStatus = .downloading
        downloadState = .downloading(progress: 0)

        do {
            try await downloader.download(from: selectedModel.remoteURL, to: modelFileURL(for: selectedModel)) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadState = .downloading(progress: progress)
                }
            }
            activeDownloader = nil
            runtimeStatus = .ready
            downloadState = .downloaded
            OtoLogger.log("Downloaded whisper.cpp model \(selectedModel.rawValue)", category: .whisper, level: .info)
        } catch is CancellationError {
            activeDownloader = nil
            runtimeStatus = modelFileExists(for: selectedModel) ? .ready : .idle
            downloadState = modelFileExists(for: selectedModel) ? .downloaded : .notDownloaded
            try? fileManager.removeItem(at: modelFileURL(for: selectedModel))
        } catch {
            activeDownloader = nil
            runtimeStatus = .error(error.localizedDescription)
            downloadState = .failed(error.localizedDescription)
            try? fileManager.removeItem(at: modelFileURL(for: selectedModel))
            OtoLogger.log("Failed to download whisper.cpp model: \(error.localizedDescription)", category: .whisper, level: .error)
        }
    }

    func cancelDownload() {
        activeDownloader?.cancel()
    }

    func deleteSelectedModel() throws {
        cancelDownload()
        let fileURL = modelFileURL(for: selectedModel)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        Task {
            await context.reset()
        }
        runtimeStatus = .idle
        downloadState = .notDownloaded
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        guard modelFileExists(for: selectedModel) else {
            runtimeStatus = .error(WhisperCppTranscriberError.modelMissing(selectedModel).localizedDescription)
            throw WhisperCppTranscriberError.modelMissing(selectedModel)
        }

        runtimeStatus = .loadingModel
        let samples = try WaveFileDecoder.decodePCM16Mono(url: audioFileURL)
        runtimeStatus = .transcribing

        let text = try await context.transcribe(
            samples: samples,
            modelPath: modelFileURL(for: selectedModel).path,
            preferredLanguage: selectedModel.rawValue.hasSuffix(".en") ? "en" : nil
        )

        guard !text.isEmpty else {
            runtimeStatus = .error(WhisperCppTranscriberError.emptyTranscription.localizedDescription)
            throw WhisperCppTranscriberError.emptyTranscription
        }

        runtimeStatus = .ready
        return text
    }

    private var snapshot: WhisperCppRuntimeSnapshot {
        WhisperCppRuntimeSnapshot(
            selectedModel: selectedModel,
            modelStatusLabel: modelStatusLabel,
            runtimeStatusLabel: runtimeStatusLabel,
            downloadState: downloadState
        )
    }

    private func emitStateChange() {
        onStateChange?(snapshot)
    }

    private func modelFileURL(for model: WhisperCppModel) -> URL {
        modelDirectoryURL.appendingPathComponent(model.filename)
    }

    private func modelFileExists(for model: WhisperCppModel) -> Bool {
        fileManager.fileExists(atPath: modelFileURL(for: model).path)
    }
}
