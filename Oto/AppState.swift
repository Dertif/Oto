import AVFoundation
import AppKit
import Foundation
import Speech
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedBackend: STTBackend = .appleSpeech {
        didSet {
            refreshWhisperModelStatus()
        }
    }
    @Published var hotkeyMode: HotkeyTriggerMode = .hold {
        didSet {
            hotkeyInterpreter.reset(for: hotkeyMode)
            coordinator.requestPermissionsRefresh(permissions: currentPermissionSnapshot(), hotkeyMode: hotkeyMode)
        }
    }
    @AppStorage("oto.qualityPreset") private var qualityPresetRawValueStorage = DictationQualityPreset.fast.rawValue
    @Published var qualityPreset: DictationQualityPreset = .fast {
        didSet {
            guard qualityPreset != oldValue else {
                return
            }
            qualityPresetRawValueStorage = qualityPreset.rawValue
            whisperTranscriber.setQualityPreset(qualityPreset)
        }
    }
    @AppStorage("oto.refinementMode") private var refinementModeRawValueStorage = TextRefinementMode.enhanced.rawValue
    @Published var refinementMode: TextRefinementMode = .enhanced {
        didSet {
            guard refinementMode != oldValue else {
                return
            }
            refinementModeRawValueStorage = refinementMode.rawValue
        }
    }
    @AppStorage("oto.allowCommandVFallback") private var allowCommandVFallbackStorage = true

    @Published var micPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var accessibilityTrusted = false

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var visualState: RecorderVisualState = .idle
    @Published var transcript = ""
    @Published var transcriptStableText = ""
    @Published var transcriptLiveText = ""
    @Published var reliabilityState: ReliabilityFlowState = .ready
    @Published var statusMessage = "Ready"
    @Published var hotkeyGuidanceMessage = "If Fn does not trigger, disable conflicting macOS Fn shortcuts and allow Input Monitoring."
    @Published var whisperModelStatusLabel = WhisperModelStatus.missing.rawValue
    @Published var whisperRuntimeStatusLabel = WhisperRuntimeStatus.idle.label
    @Published var latencySummary = "Latency P50/P95: no runs yet."
    @Published var refinementLatencySummary = "Refinement P50/P95: no runs yet."
    @Published var lastPrimaryTranscriptURL: URL?
    @Published var lastRawTranscriptURL: URL?
    @Published var lastRefinedTranscriptURL: URL?
    @Published var lastFailureContextURL: URL?
    @Published var transcriptHistoryEntries: [TranscriptHistoryEntry] = []
    @Published var transcriptHistoryError: String?
    @Published var transcriptHistoryLastUpdatedAt: Date?
    @Published var lastOutputSourceLabel = "Unknown"
    @Published var autoInjectEnabled = true
    @Published var copyToClipboardWhenAutoInjectDisabled = false
    @Published var allowCommandVFallback = true {
        didSet {
            guard allowCommandVFallback != oldValue else {
                return
            }
            allowCommandVFallbackStorage = allowCommandVFallback
        }
    }
    @Published var debugPanelEnabled = OtoLogger.debugUIPanelEnabled
    @Published var debugConfigurationSummary = OtoLogger.activeDebugFlagsSummary
    @Published var debugCurrentRunID = "None"
    @Published var debugLastEvent = "None"

    private let transcriptStore: TranscriptPersisting
    private let transcriptHistoryStore: TranscriptHistoryProviding
    private let appleTranscriber: SpeechTranscribing
    private let whisperTranscriber: WhisperTranscribing
    private let textInjectionService: TextInjecting
    private let textRefiner: TextRefining
    private let hotkeyService = GlobalHotkeyService()
    private let hotkeyInterpreter = FnHotkeyInterpreter()
    private let frontmostTracker: FrontmostAppProviding
    private let coordinator: RecordingFlowCoordinator

    init() {
        let transcriptStore: TranscriptPersisting = TranscriptStore()
        let transcriptHistoryStore: TranscriptHistoryProviding = TranscriptHistoryStore(folderURL: transcriptStore.folderURL)
        let appleTranscriber: SpeechTranscribing = AppleSpeechTranscriber()
        let whisperTranscriber: WhisperTranscribing = WhisperKitTranscriber()
        let textInjectionService: TextInjecting = TextInjectionService()
        let textRefiner: TextRefining = AppleFoundationTextRefiner()
        let audioRecorder: AudioRecording = AudioFileRecorder()
        let latencyTracker: WhisperLatencyTracking = WhisperLatencyTracker()
        let latencyRecorder: LatencyMetricsRecording = LatencyMetricsRecorder()
        let refinementLatencyRecorder: RefinementLatencyRecording = RefinementLatencyRecorder()
        let frontmostTracker: FrontmostAppProviding = FrontmostApplicationTracker()

        self.transcriptStore = transcriptStore
        self.transcriptHistoryStore = transcriptHistoryStore
        self.appleTranscriber = appleTranscriber
        self.whisperTranscriber = whisperTranscriber
        self.textInjectionService = textInjectionService
        self.textRefiner = textRefiner
        self.frontmostTracker = frontmostTracker
        self.coordinator = RecordingFlowCoordinator(
            speechTranscriber: appleTranscriber,
            whisperTranscriber: whisperTranscriber,
            audioRecorder: audioRecorder,
            transcriptStore: transcriptStore,
            textInjector: textInjectionService,
            textRefiner: textRefiner,
            latencyTracker: latencyTracker,
            latencyRecorder: latencyRecorder,
            refinementLatencyRecorder: refinementLatencyRecorder,
            frontmostAppProvider: frontmostTracker
        )

        whisperTranscriber.onRuntimeStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.whisperRuntimeStatusLabel = status.label
            }
        }

        let persistedPreset = DictationQualityPreset(rawValue: qualityPresetRawValueStorage) ?? .fast
        qualityPresetRawValueStorage = persistedPreset.rawValue
        qualityPreset = persistedPreset
        whisperTranscriber.setQualityPreset(persistedPreset)
        let persistedRefinementMode = TextRefinementMode(rawValue: refinementModeRawValueStorage) ?? .enhanced
        refinementModeRawValueStorage = persistedRefinementMode.rawValue
        refinementMode = persistedRefinementMode
        allowCommandVFallback = allowCommandVFallbackStorage

        refreshPermissionStatus()
        refreshWhisperModelStatus()
        hotkeyInterpreter.reset(for: hotkeyMode)

        coordinator.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot: snapshot)
        }
        apply(snapshot: coordinator.snapshot)

        startHotkeyMonitoring()
        frontmostTracker.start()
    }

    deinit {
        hotkeyService.stop()
        frontmostTracker.stop()
    }

    func refreshPermissionStatus() {
        micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechPermissionStatus = appleTranscriber.currentSpeechAuthorizationStatus()
        accessibilityTrusted = textInjectionService.isAccessibilityTrusted()
        coordinator.requestPermissionsRefresh(permissions: currentPermissionSnapshot(), hotkeyMode: hotkeyMode)
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionStatus()
            }
        }
    }

    func requestSpeechPermission() {
        Task {
            let status = await appleTranscriber.requestSpeechAuthorization()
            speechPermissionStatus = status
            coordinator.requestPermissionsRefresh(permissions: currentPermissionSnapshot(), hotkeyMode: hotkeyMode)
        }
    }

    func requestAccessibilityPermission() {
        textInjectionService.requestAccessibilityPermission()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            refreshPermissionStatus()
        }
    }

    func prepareWhisperRuntimeForLaunch() {
        Task {
            await whisperTranscriber.prepareForLaunch()
            refreshWhisperRuntimeStatus()
        }
    }

    func toggleRecording() {
        if isProcessing {
            return
        }

        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        let request = StartRecordingRequest(
            backend: selectedBackend,
            microphoneAuthorized: micPermissionStatus == .authorized,
            triggerMode: hotkeyMode,
            permissions: currentPermissionSnapshot()
        )
        coordinator.startRecording(request: request)
    }

    func stopRecording() {
        guard !isProcessing || isRecording else {
            return
        }

        let request = StopRecordingRequest(
            selectedBackend: selectedBackend,
            refinementMode: refinementMode,
            autoInjectEnabled: autoInjectEnabled,
            copyToClipboardWhenAutoInjectDisabled: copyToClipboardWhenAutoInjectDisabled,
            allowCommandVFallback: allowCommandVFallback,
            triggerMode: hotkeyMode,
            permissions: currentPermissionSnapshot()
        )
        coordinator.stopRecording(request: request)
    }

    func openTranscriptFolder() {
        NSWorkspace.shared.open(transcriptStore.folderURL)
    }

    func refreshTranscriptHistory() {
        do {
            transcriptHistoryEntries = try transcriptHistoryStore.loadEntries()
            transcriptHistoryError = nil
            transcriptHistoryLastUpdatedAt = Date()
        } catch {
            transcriptHistoryError = "Failed to load transcript history: \(error.localizedDescription)"
            transcriptHistoryLastUpdatedAt = Date()
            OtoLogger.log(
                "Failed to load transcript history: \(error.localizedDescription)",
                category: .artifacts,
                level: .error
            )
        }
    }

    func refreshWhisperModelStatus() {
        whisperModelStatusLabel = whisperTranscriber.refreshModelStatus().rawValue
        refreshWhisperRuntimeStatus()
    }

    func handleFnDown() {
        if !isRecording {
            startRecording()
        }
    }

    func handleFnUp() {
        if isRecording {
            stopRecording()
        }
    }

    private func handleFnToggle() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startHotkeyMonitoring() {
        hotkeyService.start { [weak self] event in
            Task { @MainActor in
                self?.handleFnHotkeyEvent(event)
            }
        }
    }

    private func handleFnHotkeyEvent(_ event: FnHotkeyEvent) {
        let intent = hotkeyInterpreter.interpret(
            isFnPressed: event.isFnPressed,
            mode: hotkeyMode,
            timestamp: event.timestamp,
            isProcessing: isProcessing
        )

        guard let intent else {
            return
        }

        switch intent {
        case .start:
            handleFnDown()
        case .stop:
            handleFnUp()
        case .toggle:
            handleFnToggle()
        }
    }

    private func refreshWhisperRuntimeStatus() {
        whisperRuntimeStatusLabel = whisperTranscriber.runtimeStatusLabel
    }

    private func apply(snapshot: FlowSnapshot) {
        let projection = AppStateMapper.map(snapshot: snapshot)

        reliabilityState = projection.reliabilityState
        isRecording = projection.isRecording
        isProcessing = projection.isProcessing
        visualState = projection.visualState
        statusMessage = projection.statusMessage
        transcriptStableText = projection.transcriptStableText
        transcriptLiveText = projection.transcriptLiveText
        transcript = [projection.transcriptStableText, projection.transcriptLiveText]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        latencySummary = projection.latencySummary
        refinementLatencySummary = projection.refinementLatencySummary
        lastPrimaryTranscriptURL = projection.primaryTranscriptURL
        lastRawTranscriptURL = projection.rawTranscriptURL
        lastRefinedTranscriptURL = projection.refinedTranscriptURL
        lastFailureContextURL = projection.failureContextURL
        lastOutputSourceLabel = projection.outputSource?.rawValue.capitalized ?? "Unknown"
        debugCurrentRunID = snapshot.runID ?? "None"
        debugLastEvent = snapshot.lastEvent.map { "\($0)" } ?? "None"
    }

    func copyDebugSummary() {
        let summary = """
        run_id: \(debugCurrentRunID)
        last_event: \(debugLastEvent)
        flow_state: \(reliabilityState.rawValue)
        backend: \(selectedBackend.rawValue)
        quality_preset: \(qualityPreset.rawValue)
        refinement_mode: \(refinementMode.rawValue)
        refinement_availability: \(textRefiner.availabilityLabel)
        output_source: \(lastOutputSourceLabel)
        hotkey_mode: \(hotkeyMode.rawValue)
        permissions: mic=\(microphoneStatusLabel), speech=\(speechStatusLabel), accessibility=\(accessibilityStatusLabel)
        whisper_runtime: \(whisperRuntimeStatusLabel)
        latency_summary: \(latencySummary)
        refinement_latency_summary: \(refinementLatencySummary)
        debug_flags: \(debugConfigurationSummary)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        statusMessage = "Copied diagnostics summary to clipboard."
    }

    var microphoneStatusLabel: String {
        switch micPermissionStatus {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    var speechStatusLabel: String {
        switch speechPermissionStatus {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    var accessibilityStatusLabel: String {
        accessibilityTrusted ? "Authorized" : "Not authorized"
    }

    private func currentPermissionSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneStatusLabel,
            speech: speechStatusLabel,
            accessibility: accessibilityStatusLabel
        )
    }
}
