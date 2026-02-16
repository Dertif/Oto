import AppKit
import AVFoundation
import Speech
import XCTest
@testable import Oto

@MainActor
final class RecordingFlowCoordinatorTests: XCTestCase {
    private func startRequest(
        backend: STTBackend = .appleSpeech,
        micAuthorized: Bool = true
    ) -> StartRecordingRequest {
        StartRecordingRequest(
            backend: backend,
            microphoneAuthorized: micAuthorized,
            triggerMode: .hold,
            permissions: PermissionSnapshot(
                microphone: "Authorized",
                speech: "Authorized",
                accessibility: "Authorized"
            )
        )
    }

    private func stopRequest(
        backend: STTBackend = .appleSpeech,
        autoInjectEnabled: Bool = true,
        copyToClipboardWhenAutoInjectDisabled: Bool = false
    ) -> StopRecordingRequest {
        StopRecordingRequest(
            selectedBackend: backend,
            autoInjectEnabled: autoInjectEnabled,
            copyToClipboardWhenAutoInjectDisabled: copyToClipboardWhenAutoInjectDisabled,
            triggerMode: .hold,
            permissions: PermissionSnapshot(
                microphone: "Authorized",
                speech: "Authorized",
                accessibility: "Authorized"
            )
        )
    }

    func testAppleHappyPathTransitionsToCompletedAndPersistsPrimaryTranscript() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello world"

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = .success(.success)
        let latency = MockLatencyTracker()
        let frontmost = MockFrontmostProvider()

        var snapshot = FlowSnapshot.initial
        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: whisper,
            audioRecorder: recorder,
            transcriptStore: store,
            textInjector: injector,
            latencyTracker: latency,
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: 10) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()

        coordinator.stopRecording(request: stopRequest())

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(snapshot.lastEvent, .injectionSucceeded(message: "Injected transcript into focused app."))
        XCTAssertNotNil(snapshot.runID)
        XCTAssertNotNil(snapshot.artifacts.primaryURL)
    }

    func testShortCaptureTransitionsToFailedAndAllowsRetry() async {
        let speech = MockSpeechTranscriber()
        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        let latency = MockLatencyTracker()
        let frontmost = MockFrontmostProvider()

        var t: TimeInterval = 0
        var snapshot = FlowSnapshot.initial

        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: whisper,
            audioRecorder: recorder,
            transcriptStore: store,
            textInjector: injector,
            latencyTracker: latency,
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: t) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        t = 0.1
        coordinator.stopRecording(request: stopRequest())

        await eventually(timeout: 1.0) {
            snapshot.phase == .failed
        }

        XCTAssertEqual(snapshot.statusMessage, "Capture was too short. Hold slightly longer and retry.")

        t = 2
        coordinator.startRecording(request: startRequest())
        await eventually(timeout: 1.0) {
            snapshot.phase == .listening
        }
    }

    func testInjectionFailureCreatesFailureContextArtifact() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = .failure(.focusedElementUnavailable)
        let latency = MockLatencyTracker()
        let frontmost = MockFrontmostProvider()

        var snapshot = FlowSnapshot.initial

        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: whisper,
            audioRecorder: recorder,
            transcriptStore: store,
            textInjector: injector,
            latencyTracker: latency,
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: 1) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest())

        await eventually(timeout: 1.0) {
            snapshot.phase == .failed
        }

        XCTAssertNotNil(snapshot.artifacts.primaryURL)
        XCTAssertNotNil(snapshot.artifacts.failureContextURL)
        XCTAssertTrue(snapshot.artifacts.failureContextURL?.lastPathComponent.contains("failure-context-") == true)
        let failureEntry = store.savedEntries
            .map(\.text)
            .first { $0.contains("[failure-context]") }
        XCTAssertNotNil(failureEntry)
        XCTAssertTrue(failureEntry?.contains("run_id:") == true)
        XCTAssertTrue(failureEntry?.contains("hotkey_mode: Hold") == true)
        XCTAssertTrue(failureEntry?.contains("microphone_permission: Authorized") == true)
    }

    func testStopRequestedDuringStartupIsDeferredUntilStartupCompletes() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"
        speech.waitForStartSignal = true

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = .success(.success)
        let latency = MockLatencyTracker()
        let frontmost = MockFrontmostProvider()

        var now: TimeInterval = 0
        var snapshot = FlowSnapshot.initial

        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: whisper,
            audioRecorder: recorder,
            transcriptStore: store,
            textInjector: injector,
            latencyTracker: latency,
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: now) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await eventually(timeout: 1.0) {
            snapshot.phase == .listening
        }

        coordinator.stopRecording(request: stopRequest())
        await Task.yield()

        XCTAssertEqual(snapshot.phase, .listening)
        XCTAssertEqual(speech.stopAndFinalizeCallCount, 0)

        now = 1
        speech.completeStart()

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(speech.stopAndFinalizeCallCount, 1)
    }

    func testSaveFailureWithAutoInjectDisabledDoesNotReportSavedTranscript() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        store.forcedSaveError = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Disk full"]
        )
        let injector = MockTextInjector()
        injector.result = .success(.success)
        let latency = MockLatencyTracker()
        let frontmost = MockFrontmostProvider()

        var snapshot = FlowSnapshot.initial

        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: whisper,
            audioRecorder: recorder,
            transcriptStore: store,
            textInjector: injector,
            latencyTracker: latency,
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: 10) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(autoInjectEnabled: false, copyToClipboardWhenAutoInjectDisabled: false))

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertTrue(snapshot.statusMessage.contains("Failed to save transcript"))
        XCTAssertNil(snapshot.artifacts.primaryURL)

        guard case let .injectionSkipped(message) = snapshot.lastEvent else {
            return XCTFail("Expected injectionSkipped event")
        }
        XCTAssertTrue(message.contains("Failed to save transcript"))
        XCTAssertFalse(message.contains("Saved transcript"))
    }

    private func eventually(timeout: TimeInterval, condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met before timeout")
    }
}

@MainActor
private final class MockSpeechTranscriber: SpeechTranscribing {
    var finalizedText = ""
    var onUpdate: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var waitForStartSignal = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    var stopAndFinalizeCallCount = 0

    func start(onUpdate: @escaping (String, Bool) -> Void, onError: @escaping (String) -> Void) async throws {
        self.onUpdate = onUpdate
        self.onError = onError
        if waitForStartSignal {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
    }

    func stop() {}

    func stopAndFinalize(timeout: TimeInterval) async -> String {
        stopAndFinalizeCallCount += 1
        return finalizedText
    }

    func completeStart() {
        waitForStartSignal = false
        startContinuation?.resume()
        startContinuation = nil
    }

    func currentSpeechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        .authorized
    }

    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        .authorized
    }
}

@MainActor
private final class MockWhisperTranscriber: WhisperTranscribing {
    var streamingEnabled: Bool = false
    var runtimeStatusLabel: String = "Ready"
    var onRuntimeStatusChange: ((WhisperRuntimeStatus) -> Void)?

    func prepareForLaunch() async {}

    func refreshModelStatus() -> WhisperModelStatus {
        .bundled
    }

    func startStreaming(onPartial: @escaping (WhisperPartialTranscript) -> Void) async throws {}

    func stopStreamingAndFinalize() async throws -> String {
        ""
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        ""
    }
}

private final class MockAudioRecorder: AudioRecording {
    func startRecording() throws -> URL {
        URL(fileURLWithPath: "/tmp/mock.wav")
    }

    func stopRecording() -> URL? {
        URL(fileURLWithPath: "/tmp/mock.wav")
    }
}

private final class MockTranscriptStore: TranscriptPersisting {
    let folderURL = URL(fileURLWithPath: "/tmp")
    private var index = 0
    var forcedSaveError: Error?
    private(set) var savedEntries: [(text: String, backend: STTBackend)] = []

    func save(text: String, backend: STTBackend, prefix: String) throws -> URL {
        if let forcedSaveError {
            throw forcedSaveError
        }
        savedEntries.append((text: text, backend: backend))
        index += 1
        return URL(fileURLWithPath: "/tmp/\(prefix)-\(index).txt")
    }
}

@MainActor
private final class MockTextInjector: TextInjecting {
    var result: Result<TextInjectionOutcome, TextInjectionError> = .success(.success)

    func isAccessibilityTrusted() -> Bool {
        true
    }

    func requestAccessibilityPermission() {}

    func inject(text: String, preferredApplication: NSRunningApplication?) async -> Result<TextInjectionOutcome, TextInjectionError> {
        result
    }
}

private final class MockLatencyTracker: WhisperLatencyTracking {
    func beginRun(usingStreaming: Bool, at date: Date) {}
    func markFirstPartial(at date: Date) {}
    func markStopRequested(at date: Date) {}
    func finish(at date: Date) -> WhisperLatencyMetrics? { nil }
    func reset() {}
}

private final class MockFrontmostProvider: FrontmostAppProviding {
    var frontmostApplication: NSRunningApplication?
    func start() {}
    func stop() {}
}
