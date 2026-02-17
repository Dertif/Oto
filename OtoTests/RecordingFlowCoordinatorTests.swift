import AppKit
import AVFoundation
import Speech
import XCTest
@testable import Oto

@MainActor
final class RecordingFlowCoordinatorTests: XCTestCase {
    private func successInjectionReport(_ outcome: TextInjectionOutcome = .success) -> TextInjectionReport {
        .success(outcome, diagnostics: diagnostics())
    }

    private func failureInjectionReport(_ error: TextInjectionError) -> TextInjectionReport {
        .failure(error, diagnostics: diagnostics())
    }

    private func diagnostics(
        attempts: [InjectionAttempt] = [],
        finalStrategy: InjectionStrategy? = nil
    ) -> TextInjectionDiagnostics {
        TextInjectionDiagnostics(
            strategyChain: InjectionStrategy.allCases,
            attempts: attempts,
            finalStrategy: finalStrategy,
            focusedRole: "AXTextField",
            focusedSubrole: nil,
            focusedProcessID: 42,
            focusWaitMilliseconds: 150,
            preferredAppBundleID: "com.apple.TextEdit",
            preferredAppActivated: true,
            frontmostAppBundleID: "com.apple.TextEdit"
        )
    }

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
        refinementMode: TextRefinementMode = .raw,
        autoInjectEnabled: Bool = true,
        copyToClipboardWhenAutoInjectDisabled: Bool = false,
        allowCommandVFallback: Bool = false
    ) -> StopRecordingRequest {
        StopRecordingRequest(
            selectedBackend: backend,
            refinementMode: refinementMode,
            autoInjectEnabled: autoInjectEnabled,
            copyToClipboardWhenAutoInjectDisabled: copyToClipboardWhenAutoInjectDisabled,
            allowCommandVFallback: allowCommandVFallback,
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
        injector.result = successInjectionReport(.success)
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
            latencyRecorder: LatencyMetricsRecorder(),
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
        XCTAssertTrue(snapshot.latencySummary.contains("Apple Speech"))
    }

    func testWhisperRunPublishesBackendLatencySummary() async {
        let speech = MockSpeechTranscriber()
        let whisper = MockWhisperTranscriber()
        whisper.finalizedText = "hello whisper"
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = successInjectionReport(.success)
        let latency = MockLatencyTracker()
        latency.finishedMetrics = WhisperLatencyMetrics(
            usedStreaming: false,
            timeToFirstPartial: nil,
            stopToFinalTranscript: 0.30,
            totalDuration: 1.80
        )
        let metricsRecorder = MockLatencyRecorder()
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
            latencyRecorder: metricsRecorder,
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: now) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest(backend: .whisper))
        await Task.yield()
        now = 2.0
        coordinator.stopRecording(request: stopRequest(backend: .whisper))

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertGreaterThan(latency.finishCallCount, 0)
        XCTAssertEqual(metricsRecorder.recordedMetrics.first?.backend, .whisper)
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
            latencyRecorder: LatencyMetricsRecorder(),
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

    func testSoftInjectionFailureSkipsInjectionAndCreatesFailureContextArtifact() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = failureInjectionReport(.focusStabilizationTimedOut)
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
            latencyRecorder: LatencyMetricsRecorder(),
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
            snapshot.phase == .completed
        }

        XCTAssertNotNil(snapshot.artifacts.primaryURL)
        XCTAssertNotNil(snapshot.artifacts.failureContextURL)
        XCTAssertTrue(snapshot.artifacts.failureContextURL?.lastPathComponent.contains("failure-context-") == true)
        XCTAssertTrue(snapshot.statusMessage.contains("Injection skipped: Timed out while waiting for a focused target."))
        let failureEntry = store.savedEntries
            .map(\.text)
            .first { $0.contains("[failure-context]") }
        XCTAssertNotNil(failureEntry)
        XCTAssertTrue(failureEntry?.contains("run_id:") == true)
        XCTAssertTrue(failureEntry?.contains("hotkey_mode: Hold") == true)
        XCTAssertTrue(failureEntry?.contains("microphone_permission: Authorized") == true)
        XCTAssertTrue(failureEntry?.contains("injection_strategy_chain:") == true)
        XCTAssertTrue(failureEntry?.contains("injection_attempts:") == true)
        XCTAssertTrue(failureEntry?.contains("focused_role:") == true)
        XCTAssertTrue(failureEntry?.contains("focus_wait_ms:") == true)
        XCTAssertTrue(failureEntry?.contains("preferred_app_bundle_id:") == true)
    }

    func testHardInjectionFailureStillTransitionsToFailed() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = failureInjectionReport(.eventSourceUnavailable)
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
            latencyRecorder: LatencyMetricsRecorder(),
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

        XCTAssertTrue(snapshot.statusMessage.contains("Injection failed: Unable to generate keyboard events for injection."))
        XCTAssertNotNil(snapshot.artifacts.failureContextURL)
    }

    func testStopRequestedDuringStartupIsDeferredUntilStartupCompletes() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"
        speech.waitForStartSignal = true

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = successInjectionReport(.success)
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
            latencyRecorder: LatencyMetricsRecorder(),
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
        injector.result = successInjectionReport(.success)
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
            latencyRecorder: LatencyMetricsRecorder(),
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

    func testAllowCommandVFallbackIsForwardedToInjectorRequest() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = "hello"

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = successInjectionReport(.success)
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
            latencyRecorder: LatencyMetricsRecorder(),
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: 10) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(allowCommandVFallback: true))

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(injector.lastRequest?.allowCommandVFallback, true)
    }

    func testAppleEmptyFinalizationUsesLatestPartialFallback() async {
        let speech = MockSpeechTranscriber()
        speech.finalizedText = ""

        let whisper = MockWhisperTranscriber()
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = successInjectionReport(.success)
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
            latencyRecorder: LatencyMetricsRecorder(),
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: 10) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        speech.onUpdate?("speech from partial", false)
        coordinator.stopRecording(request: stopRequest())

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(snapshot.finalTranscriptText, "speech from partial")
        XCTAssertNotNil(snapshot.artifacts.failureContextURL)
        XCTAssertTrue(snapshot.statusMessage.contains("Injected transcript"))
    }

    func testWhisperEmptyFinalizationUsesLatestPartialFallback() async {
        let speech = MockSpeechTranscriber()
        let whisper = MockWhisperTranscriber()
        whisper.streamingEnabled = true
        whisper.streamingPartialToEmit = WhisperPartialTranscript(stableText: "hello", liveText: "world")
        whisper.stopStreamingError = WhisperKitTranscriberError.emptyTranscription
        let recorder = MockAudioRecorder()
        let store = MockTranscriptStore()
        let injector = MockTextInjector()
        injector.result = successInjectionReport(.success)
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
            latencyRecorder: LatencyMetricsRecorder(),
            frontmostAppProvider: frontmost,
            nowProvider: { Date(timeIntervalSince1970: 10) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest(backend: .whisper))
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(backend: .whisper))

        await eventually(timeout: 1.0) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(snapshot.finalTranscriptText, "hello world")
        XCTAssertNotNil(snapshot.artifacts.failureContextURL)
        XCTAssertTrue(snapshot.statusMessage.contains("Injected transcript"))
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
    var qualityPreset: DictationQualityPreset = .fast
    var onRuntimeStatusChange: ((WhisperRuntimeStatus) -> Void)?
    var finalizedText = ""
    var streamingPartialToEmit: WhisperPartialTranscript?
    var stopStreamingError: Error?
    var transcribeError: Error?

    func setQualityPreset(_ preset: DictationQualityPreset) {
        qualityPreset = preset
    }

    func prepareForLaunch() async {}

    func refreshModelStatus() -> WhisperModelStatus {
        .bundled
    }

    func startStreaming(onPartial: @escaping (WhisperPartialTranscript) -> Void) async throws {
        if let streamingPartialToEmit {
            onPartial(streamingPartialToEmit)
        }
    }

    func stopStreamingAndFinalize() async throws -> String {
        if let stopStreamingError {
            throw stopStreamingError
        }
        return finalizedText
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        if let transcribeError {
            throw transcribeError
        }
        return finalizedText
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
    var result: TextInjectionReport = .success(
        .success,
        diagnostics: TextInjectionDiagnostics(
            strategyChain: InjectionStrategy.allCases,
            attempts: [],
            finalStrategy: .axInsertText,
            focusedRole: nil,
            focusedSubrole: nil,
            focusedProcessID: nil,
            focusWaitMilliseconds: 0,
            preferredAppBundleID: nil,
            preferredAppActivated: false,
            frontmostAppBundleID: nil
        )
    )
    private(set) var lastRequest: TextInjectionRequest?

    func isAccessibilityTrusted() -> Bool {
        true
    }

    func requestAccessibilityPermission() {}

    func inject(request: TextInjectionRequest) async -> TextInjectionReport {
        lastRequest = request
        return result
    }
}

private final class MockLatencyTracker: WhisperLatencyTracking {
    var finishedMetrics: WhisperLatencyMetrics?
    private(set) var finishCallCount = 0

    func beginRun(usingStreaming: Bool, at date: Date) {}
    func markFirstPartial(at date: Date) {}
    func markStopRequested(at date: Date) {}
    func finish(at date: Date) -> WhisperLatencyMetrics? {
        finishCallCount += 1
        return finishedMetrics
    }
    func reset() {}
}

@MainActor
private final class MockLatencyRecorder: LatencyMetricsRecording {
    private(set) var recordedMetrics: [BackendLatencyMetrics] = []

    func record(_ metrics: BackendLatencyMetrics) {
        recordedMetrics.append(metrics)
    }

    func summary() -> String {
        guard !recordedMetrics.isEmpty else {
            return "Latency P50/P95: no runs yet."
        }
        return "Latency P50/P95 - mocked"
    }

    func aggregates() -> [BackendLatencyAggregate] {
        []
    }
}

private final class MockFrontmostProvider: FrontmostAppProviding {
    var frontmostApplication: NSRunningApplication?
    func start() {}
    func stop() {}
}
