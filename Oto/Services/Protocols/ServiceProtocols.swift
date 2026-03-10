import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
protocol SpeechTranscribing: AnyObject {
    func start(
        onUpdate: @escaping (String, Bool) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (String) -> Void
    ) async throws
    func stop()
    func stopAndFinalize(timeout: TimeInterval) async -> String
    func currentSpeechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus
    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
}

@MainActor
protocol WhisperTranscribing: AnyObject {
    var streamingEnabled: Bool { get }
    var runtimeStatusLabel: String { get }
    var onRuntimeStatusChange: ((WhisperRuntimeStatus) -> Void)? { get set }
    var qualityPreset: DictationQualityPreset { get }
    func setQualityPreset(_ preset: DictationQualityPreset)
    func prepareForLaunch() async
    @discardableResult func refreshModelStatus() -> WhisperModelStatus
    func startStreaming(
        onPartial: @escaping (WhisperPartialTranscript) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) async throws
    func stopStreamingAndFinalize() async throws -> String
    func transcribe(audioFileURL: URL) async throws -> String
}

enum WhisperCppModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(String)

    var progressValue: Double? {
        guard case let .downloading(progress) = self else {
            return nil
        }
        return progress
    }

    var label: String {
        switch self {
        case .notDownloaded:
            return "Not downloaded"
        case let .downloading(progress):
            return "Downloading \(Int(progress * 100))%"
        case .downloaded:
            return "Downloaded"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }
}

struct WhisperCppRuntimeSnapshot: Equatable {
    let selectedModel: WhisperCppModel
    let modelStatusLabel: String
    let runtimeStatusLabel: String
    let downloadState: WhisperCppModelDownloadState
}

@MainActor
protocol WhisperCppTranscribing: AnyObject {
    var selectedModel: WhisperCppModel { get }
    var supportedModels: [WhisperCppModel] { get }
    var runtimeStatusLabel: String { get }
    var modelStatusLabel: String { get }
    var downloadState: WhisperCppModelDownloadState { get }
    var onStateChange: ((WhisperCppRuntimeSnapshot) -> Void)? { get set }
    func prepareForLaunch() async
    func refreshState() -> WhisperCppRuntimeSnapshot
    func selectModel(_ model: WhisperCppModel)
    func downloadSelectedModel() async
    func cancelDownload()
    func deleteSelectedModel() throws
    func transcribe(audioFileURL: URL) async throws -> String
}

protocol AudioRecording: AnyObject {
    func startRecording(onAudioLevel: @escaping (Float) -> Void) throws -> URL
    @discardableResult func stopRecording() -> URL?
}

protocol TranscriptPersisting: AnyObject {
    var folderURL: URL { get }
    func save(text: String, backend: STTBackend, prefix: String) throws -> URL
}

extension TranscriptPersisting {
    func save(text: String, backend: STTBackend) throws -> URL {
        try save(text: text, backend: backend, prefix: "transcript")
    }
}

@MainActor
protocol TextInjecting: AnyObject {
    func isAccessibilityTrusted() -> Bool
    func requestAccessibilityPermission()
    func inject(request: TextInjectionRequest) async -> TextInjectionReport
}

protocol WhisperLatencyTracking: AnyObject {
    func beginRun(usingStreaming: Bool, at date: Date)
    func markFirstPartial(at date: Date)
    func markStopRequested(at date: Date)
    func finish(at date: Date) -> WhisperLatencyMetrics?
    func reset()
}

protocol FrontmostAppProviding: AnyObject {
    var frontmostApplication: NSRunningApplication? { get }
    func start()
    func stop()
}

protocol TextRefining: AnyObject {
    var availabilityLabel: String { get }
    func refine(request: TextRefinementRequest) async -> TextRefinementResult
}

@MainActor
protocol RefinementLatencyRecording: AnyObject {
    func record(_ metrics: RefinementLatencyMetrics)
    func summary() -> String
    func aggregates() -> [RefinementLatencyAggregate]
}

extension SpeechTranscribing {
    func start(
        onUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void
    ) async throws {
        try await start(onUpdate: onUpdate, onAudioLevel: { _ in }, onError: onError)
    }
}

extension WhisperTranscribing {
    func startStreaming(onPartial: @escaping (WhisperPartialTranscript) -> Void) async throws {
        try await startStreaming(onPartial: onPartial, onAudioLevel: { _ in })
    }
}

extension AudioRecording {
    func startRecording() throws -> URL {
        try startRecording(onAudioLevel: { _ in })
    }
}
