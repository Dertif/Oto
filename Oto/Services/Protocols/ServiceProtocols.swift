import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
protocol SpeechTranscribing: AnyObject {
    func start(
        onUpdate: @escaping (String, Bool) -> Void,
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
    func prepareForLaunch() async
    @discardableResult func refreshModelStatus() -> WhisperModelStatus
    func startStreaming(onPartial: @escaping (WhisperPartialTranscript) -> Void) async throws
    func stopStreamingAndFinalize() async throws -> String
    func transcribe(audioFileURL: URL) async throws -> String
}

protocol AudioRecording: AnyObject {
    func startRecording() throws -> URL
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
    func inject(text: String, preferredApplication: NSRunningApplication?) async -> Result<TextInjectionOutcome, TextInjectionError>
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
