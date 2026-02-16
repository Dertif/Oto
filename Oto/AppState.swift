import AVFoundation
import AppKit
import Foundation
import Speech

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
        }
    }
    @Published var micPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var isRecording = false {
        didSet {
            updateVisualState()
        }
    }
    @Published var isProcessing = false {
        didSet {
            updateVisualState()
        }
    }
    @Published var visualState: RecorderVisualState = .idle
    @Published var transcript = ""
    @Published var transcriptStableText = ""
    @Published var transcriptLiveText = ""
    @Published var statusMessage = "Ready"
    @Published var hotkeyGuidanceMessage = "If Fn does not trigger, disable conflicting macOS Fn shortcuts and allow Input Monitoring."
    @Published var whisperModelStatusLabel = WhisperModelStatus.missing.rawValue
    @Published var whisperRuntimeStatusLabel = WhisperRuntimeStatus.idle.label
    @Published var whisperLatencySummary = "Whisper latency: no runs yet."
    @Published var lastSavedTranscriptURL: URL?

    private let transcriptStore = TranscriptStore()
    private let appleTranscriber = AppleSpeechTranscriber()
    private let whisperTranscriber = WhisperKitTranscriber()
    private let audioRecorder = AudioFileRecorder()
    private let hotkeyService = GlobalHotkeyService()
    private let hotkeyInterpreter = FnHotkeyInterpreter()
    private let whisperLatencyTracker = WhisperLatencyTracker()
    private var activeRecordingBackend: STTBackend?
    private var activeWhisperCaptureMode: WhisperCaptureMode?

    private enum WhisperCaptureMode {
        case streaming
        case file
    }

    init() {
        refreshPermissionStatus()
        refreshWhisperModelStatus()
        hotkeyInterpreter.reset(for: hotkeyMode)
        startHotkeyMonitoring()
    }

    deinit {
        hotkeyService.stop()
    }

    func refreshPermissionStatus() {
        micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechPermissionStatus = appleTranscriber.currentSpeechAuthorizationStatus()
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
        guard !isProcessing else {
            return
        }

        refreshPermissionStatus()
        refreshWhisperModelStatus()

        guard micPermissionStatus == .authorized else {
            statusMessage = "Microphone access is required."
            return
        }

        transcript = ""
        transcriptStableText = ""
        transcriptLiveText = ""

        let backendToStart = selectedBackend

        switch backendToStart {
        case .appleSpeech:
            activeRecordingBackend = .appleSpeech
            statusMessage = "Listening with Apple Speech..."
            Task {
                do {
                    try await appleTranscriber.start(
                        onUpdate: { [weak self] text, _ in
                            Task { @MainActor in
                                self?.transcript = text
                                self?.transcriptStableText = text
                                self?.transcriptLiveText = ""
                            }
                        },
                        onError: { [weak self] message in
                            Task { @MainActor in
                                guard let self else {
                                    return
                                }
                                if !self.isRecording &&
                                    !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                    message.lowercased().contains("no speech detected")
                                {
                                    return
                                }
                                self.statusMessage = "Speech error: \(message)"
                            }
                        }
                    )
                    isRecording = true
                } catch {
                    activeRecordingBackend = nil
                    statusMessage = "Unable to start: \(error.localizedDescription)"
                    isRecording = false
                    refreshPermissionStatus()
                }
            }

        case .whisper:
            statusMessage = "Starting WhisperKit..."
            Task {
                do {
                    try await startWhisperCapture()
                    activeRecordingBackend = .whisper
                    isRecording = true
                    statusMessage = activeWhisperCaptureMode == .streaming
                        ? "Listening with WhisperKit..."
                        : "Recording with WhisperKit..."
                    refreshWhisperRuntimeStatus()
                } catch {
                    activeRecordingBackend = nil
                    activeWhisperCaptureMode = nil
                    whisperLatencyTracker.reset()
                    statusMessage = "Unable to start Whisper recording: \(error.localizedDescription)"
                    isRecording = false
                    refreshWhisperRuntimeStatus()
                }
            }
        }
    }

    func stopRecording() {
        guard !isProcessing else {
            return
        }

        let backendToStop = activeRecordingBackend ?? selectedBackend

        switch backendToStop {
        case .appleSpeech:
            appleTranscriber.stop()
            activeRecordingBackend = nil
            isRecording = false
            statusMessage = "Stopped"
            saveTranscript(text: transcript, backend: .appleSpeech)

        case .whisper:
            isRecording = false
            activeRecordingBackend = nil
            whisperLatencyTracker.markStopRequested()

            let captureMode = activeWhisperCaptureMode
            activeWhisperCaptureMode = nil
            let audioURL = captureMode == .file ? audioRecorder.stopRecording() : nil

            if captureMode == .file, audioURL == nil {
                statusMessage = "No Whisper recording was found."
                finalizeWhisperLatencyRun()
                return
            }

            statusMessage = "Transcribing with WhisperKit..."
            isProcessing = true

            Task {
                defer {
                    isProcessing = false
                    refreshWhisperModelStatus()
                }

                do {
                    let text: String
                    switch captureMode {
                    case .streaming:
                        text = try await whisperTranscriber.stopStreamingAndFinalize()
                    case .file:
                        guard let audioURL else {
                            throw WhisperKitTranscriberError.streamingNotAvailable
                        }
                        text = try await whisperTranscriber.transcribe(audioFileURL: audioURL)
                    case .none:
                        throw WhisperKitTranscriberError.streamingNotAvailable
                    }

                    transcript = text
                    transcriptStableText = text
                    transcriptLiveText = ""
                    saveTranscript(text: text, backend: .whisper)
                    finalizeWhisperLatencyRun()
                } catch {
                    statusMessage = "WhisperKit failed: \(error.localizedDescription)"
                    finalizeWhisperLatencyRun()
                }
            }
        }
    }

    private func saveTranscript(text: String, backend: STTBackend) {
        do {
            let savedURL = try transcriptStore.save(text: text, backend: backend)
            lastSavedTranscriptURL = savedURL
            statusMessage = "Saved transcript"
        } catch {
            statusMessage = "Failed to save transcript: \(error.localizedDescription)"
        }
    }

    func openTranscriptFolder() {
        NSWorkspace.shared.open(transcriptStore.folderURL)
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

    private func updateVisualState() {
        if isProcessing {
            visualState = .processing
            return
        }
        if isRecording {
            visualState = .recording
            return
        }
        visualState = .idle
    }

    private func refreshWhisperRuntimeStatus() {
        whisperRuntimeStatusLabel = whisperTranscriber.runtimeStatusLabel
    }

    private func startWhisperCapture() async throws {
        if whisperTranscriber.streamingEnabled {
            try await startWhisperStreamingCapture()
            return
        }

        try startWhisperFileCapture()
    }

    private func startWhisperStreamingCapture() async throws {
        whisperLatencyTracker.beginRun(usingStreaming: true)
        activeWhisperCaptureMode = .streaming

        do {
            try await whisperTranscriber.startStreaming { [weak self] partial in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.transcriptStableText = partial.stableText
                    self.transcriptLiveText = partial.liveText
                    self.transcript = partial.combinedText
                    if !partial.combinedText.isEmpty {
                        self.whisperLatencyTracker.markFirstPartial()
                    }
                }
            }
        } catch {
            // Streaming remains the default. If runtime streaming setup fails,
            // we keep Whisper usable by falling back to file-based capture.
            whisperLatencyTracker.reset()
            try startWhisperFileCapture()
        }
    }

    private func startWhisperFileCapture() throws {
        _ = try audioRecorder.startRecording()
        whisperLatencyTracker.beginRun(usingStreaming: false)
        activeWhisperCaptureMode = .file
    }

    private func finalizeWhisperLatencyRun() {
        guard let metrics = whisperLatencyTracker.finish() else {
            return
        }
        whisperLatencySummary = metrics.summary
        print("[Oto][WhisperLatency] \(metrics.summary)")
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
}
