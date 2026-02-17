import AppKit
import AVFoundation
import Speech
import XCTest
@testable import Oto

@MainActor
final class RecordingFlowCoordinatorRefinementTests: XCTestCase {
    private func startRequest(backend: STTBackend = .appleSpeech) -> StartRecordingRequest {
        StartRecordingRequest(
            backend: backend,
            microphoneAuthorized: true,
            triggerMode: .hold,
            permissions: PermissionSnapshot(
                microphone: "Authorized",
                speech: "Authorized",
                accessibility: "Authorized"
            )
        )
    }

    private func stopRequest(refinementMode: TextRefinementMode) -> StopRecordingRequest {
        StopRecordingRequest(
            selectedBackend: .appleSpeech,
            refinementMode: refinementMode,
            autoInjectEnabled: true,
            copyToClipboardWhenAutoInjectDisabled: false,
            allowCommandVFallback: false,
            triggerMode: .hold,
            permissions: PermissionSnapshot(
                microphone: "Authorized",
                speech: "Authorized",
                accessibility: "Authorized"
            )
        )
    }

    func testEnhancedSuccessInjectsRefinedTextAndPersistsRawAndRefinedArtifacts() async {
        let speech = RefinementMockSpeechTranscriber()
        speech.finalizedText = "hello world"
        let refiner = RefinementMockTextRefiner()
        refiner.nextResult = .refined(
            text: "Hello, world.",
            mode: .enhanced,
            availability: "Available",
            latency: 0.45
        )

        let store = RefinementMockTranscriptStore()
        let injector = RefinementMockTextInjector()
        let refinementRecorder = RefinementMockRefinementLatencyRecorder()

        var snapshot = FlowSnapshot.initial
        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: RefinementMockWhisperTranscriber(),
            audioRecorder: RefinementMockAudioRecorder(),
            transcriptStore: store,
            textInjector: injector,
            textRefiner: refiner,
            latencyTracker: RefinementMockLatencyTracker(),
            latencyRecorder: RefinementMockLatencyRecorder(),
            refinementLatencyRecorder: refinementRecorder,
            frontmostAppProvider: RefinementMockFrontmostProvider(),
            nowProvider: { Date(timeIntervalSince1970: 10) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(refinementMode: .enhanced))

        await eventually(timeout: 1) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(refiner.callCount, 1)
        XCTAssertEqual(snapshot.outputSource, .refined)
        XCTAssertEqual(injector.lastRequest?.text, "Hello, world.")
        XCTAssertNotNil(snapshot.artifacts.rawURL)
        XCTAssertNotNil(snapshot.artifacts.refinedURL)
        XCTAssertNotNil(snapshot.artifacts.primaryURL)
        XCTAssertEqual(snapshot.artifacts.primaryURL, snapshot.artifacts.refinedURL)
        XCTAssertTrue(store.savedPrefixes.contains("raw-transcript"))
        XCTAssertTrue(store.savedPrefixes.contains("refined-transcript"))
        XCTAssertEqual(refinementRecorder.recorded.count, 1)
    }

    func testEnhancedUnavailableFallsBackToRawAndShowsSoftWarning() async {
        let speech = RefinementMockSpeechTranscriber()
        speech.finalizedText = "hello world"
        let refiner = RefinementMockTextRefiner()
        refiner.nextResult = .raw(
            text: "hello world",
            mode: .enhanced,
            availability: "Unavailable",
            fallbackReason: "refiner_unavailable"
        )

        let store = RefinementMockTranscriptStore()
        let injector = RefinementMockTextInjector()

        var snapshot = FlowSnapshot.initial
        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: RefinementMockWhisperTranscriber(),
            audioRecorder: RefinementMockAudioRecorder(),
            transcriptStore: store,
            textInjector: injector,
            textRefiner: refiner,
            latencyTracker: RefinementMockLatencyTracker(),
            latencyRecorder: RefinementMockLatencyRecorder(),
            refinementLatencyRecorder: RefinementMockRefinementLatencyRecorder(),
            frontmostAppProvider: RefinementMockFrontmostProvider(),
            nowProvider: { Date(timeIntervalSince1970: 20) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(refinementMode: .enhanced))

        await eventually(timeout: 1) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(snapshot.outputSource, .raw)
        XCTAssertEqual(injector.lastRequest?.text, "hello world")
        XCTAssertTrue(snapshot.statusMessage.contains("Refinement fallback: refiner_unavailable"))
        XCTAssertEqual(snapshot.refinementDiagnostics?.fallbackReason, "refiner_unavailable")
        XCTAssertTrue(store.savedPrefixes.contains("raw-transcript"))
    }

    func testEnhancedGuardrailViolationFallsBackToRaw() async {
        let speech = RefinementMockSpeechTranscriber()
        speech.finalizedText = "Deploy version 123 tomorrow."
        let refiner = RefinementMockTextRefiner()
        refiner.nextResult = .refined(
            text: "Deploy version 124 tomorrow.",
            mode: .enhanced,
            availability: "Available",
            latency: 0.2
        )

        var snapshot = FlowSnapshot.initial
        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: RefinementMockWhisperTranscriber(),
            audioRecorder: RefinementMockAudioRecorder(),
            transcriptStore: RefinementMockTranscriptStore(),
            textInjector: RefinementMockTextInjector(),
            textRefiner: refiner,
            latencyTracker: RefinementMockLatencyTracker(),
            latencyRecorder: RefinementMockLatencyRecorder(),
            refinementLatencyRecorder: RefinementMockRefinementLatencyRecorder(),
            frontmostAppProvider: RefinementMockFrontmostProvider(),
            nowProvider: { Date(timeIntervalSince1970: 30) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(refinementMode: .enhanced))

        await eventually(timeout: 1) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(snapshot.outputSource, .raw)
        XCTAssertEqual(snapshot.refinementDiagnostics?.fallbackReason, "guardrail_numeric_token_mismatch")
        XCTAssertTrue(snapshot.statusMessage.contains("guardrail_numeric_token_mismatch"))
    }

    func testRawModeBypassesRefiner() async {
        let speech = RefinementMockSpeechTranscriber()
        speech.finalizedText = "hello world"
        let refiner = RefinementMockTextRefiner()

        var snapshot = FlowSnapshot.initial
        let coordinator = RecordingFlowCoordinator(
            speechTranscriber: speech,
            whisperTranscriber: RefinementMockWhisperTranscriber(),
            audioRecorder: RefinementMockAudioRecorder(),
            transcriptStore: RefinementMockTranscriptStore(),
            textInjector: RefinementMockTextInjector(),
            textRefiner: refiner,
            latencyTracker: RefinementMockLatencyTracker(),
            latencyRecorder: RefinementMockLatencyRecorder(),
            refinementLatencyRecorder: RefinementMockRefinementLatencyRecorder(),
            frontmostAppProvider: RefinementMockFrontmostProvider(),
            nowProvider: { Date(timeIntervalSince1970: 40) }
        )
        coordinator.onSnapshot = { latest in
            snapshot = latest
        }

        coordinator.startRecording(request: startRequest())
        await Task.yield()
        coordinator.stopRecording(request: stopRequest(refinementMode: .raw))

        await eventually(timeout: 1) {
            snapshot.phase == .completed
        }

        XCTAssertEqual(refiner.callCount, 0)
        XCTAssertEqual(snapshot.outputSource, .raw)
        XCTAssertFalse(snapshot.statusMessage.contains("Refinement fallback"))
        XCTAssertNil(snapshot.artifacts.rawURL)
        XCTAssertNil(snapshot.artifacts.refinedURL)
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
private final class RefinementMockSpeechTranscriber: SpeechTranscribing {
    var finalizedText = ""

    func start(onUpdate: @escaping (String, Bool) -> Void, onError: @escaping (String) -> Void) async throws {}
    func stop() {}
    func stopAndFinalize(timeout: TimeInterval) async -> String { finalizedText }
    func currentSpeechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { .authorized }
    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus { .authorized }
}

@MainActor
private final class RefinementMockWhisperTranscriber: WhisperTranscribing {
    var streamingEnabled: Bool = false
    var runtimeStatusLabel: String = "Ready"
    var qualityPreset: DictationQualityPreset = .fast
    var onRuntimeStatusChange: ((WhisperRuntimeStatus) -> Void)?

    func setQualityPreset(_ preset: DictationQualityPreset) { qualityPreset = preset }
    func prepareForLaunch() async {}
    func refreshModelStatus() -> WhisperModelStatus { .bundled }
    func startStreaming(onPartial: @escaping (WhisperPartialTranscript) -> Void) async throws {}
    func stopStreamingAndFinalize() async throws -> String { "" }
    func transcribe(audioFileURL: URL) async throws -> String { "" }
}

private final class RefinementMockAudioRecorder: AudioRecording {
    func startRecording() throws -> URL { URL(fileURLWithPath: "/tmp/mock.wav") }
    func stopRecording() -> URL? { URL(fileURLWithPath: "/tmp/mock.wav") }
}

private final class RefinementMockTranscriptStore: TranscriptPersisting {
    let folderURL = URL(fileURLWithPath: "/tmp")
    private var index = 0
    private(set) var savedPrefixes: [String] = []

    func save(text: String, backend: STTBackend, prefix: String) throws -> URL {
        savedPrefixes.append(prefix)
        index += 1
        return URL(fileURLWithPath: "/tmp/\(prefix)-\(index).txt")
    }
}

@MainActor
private final class RefinementMockTextInjector: TextInjecting {
    private(set) var lastRequest: TextInjectionRequest?

    func isAccessibilityTrusted() -> Bool { true }
    func requestAccessibilityPermission() {}
    func inject(request: TextInjectionRequest) async -> TextInjectionReport {
        lastRequest = request
        return .success(
            .success,
            diagnostics: TextInjectionDiagnostics(
                strategyChain: InjectionStrategy.allCases,
                attempts: [],
                finalStrategy: .axInsertText,
                focusedRole: "AXTextField",
                focusedSubrole: nil,
                focusedProcessID: 42,
                focusWaitMilliseconds: 10,
                preferredAppBundleID: "com.apple.TextEdit",
                preferredAppActivated: true,
                frontmostAppBundleID: "com.apple.TextEdit"
            )
        )
    }
}

private final class RefinementMockTextRefiner: TextRefining {
    var availabilityLabel: String = "Available"
    var nextResult: TextRefinementResult?
    private(set) var callCount = 0

    func refine(request: TextRefinementRequest) async -> TextRefinementResult {
        callCount += 1
        if let nextResult {
            return nextResult
        }
        return .raw(
            text: request.rawText,
            mode: request.mode,
            availability: availabilityLabel,
            fallbackReason: "refiner_unavailable"
        )
    }
}

private final class RefinementMockLatencyTracker: WhisperLatencyTracking {
    func beginRun(usingStreaming: Bool, at date: Date) {}
    func markFirstPartial(at date: Date) {}
    func markStopRequested(at date: Date) {}
    func finish(at date: Date) -> WhisperLatencyMetrics? { nil }
    func reset() {}
}

@MainActor
private final class RefinementMockLatencyRecorder: LatencyMetricsRecording {
    func record(_ metrics: BackendLatencyMetrics) {}
    func summary() -> String { "Latency P50/P95: no runs yet." }
    func aggregates() -> [BackendLatencyAggregate] { [] }
}

@MainActor
private final class RefinementMockRefinementLatencyRecorder: RefinementLatencyRecording {
    private(set) var recorded: [RefinementLatencyMetrics] = []

    func record(_ metrics: RefinementLatencyMetrics) {
        recorded.append(metrics)
    }

    func summary() -> String {
        guard !recorded.isEmpty else {
            return "Refinement P50/P95: no runs yet."
        }
        return "Refinement P50/P95 - mocked"
    }

    func aggregates() -> [RefinementLatencyAggregate] {
        []
    }
}

private final class RefinementMockFrontmostProvider: FrontmostAppProviding {
    var frontmostApplication: NSRunningApplication?
    func start() {}
    func stop() {}
}
