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
    @Published var statusMessage = "Ready"
    @Published var hotkeyGuidanceMessage = "If Fn does not trigger, disable conflicting macOS Fn shortcuts and allow Input Monitoring."
    @Published var whisperModelStatusLabel = WhisperModelStatus.missing.rawValue
    @Published var lastSavedTranscriptURL: URL?

    private let transcriptStore = TranscriptStore()
    private let appleTranscriber = AppleSpeechTranscriber()
    private let whisperTranscriber = WhisperKitTranscriber()
    private let audioRecorder = AudioFileRecorder()
    private let hotkeyService = GlobalHotkeyService()
    private let hotkeyInterpreter = FnHotkeyInterpreter()
    private var activeRecordingBackend: STTBackend?

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
                            }
                        },
                        onError: { [weak self] message in
                            Task { @MainActor in
                                self?.statusMessage = "Speech error: \(message)"
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
            do {
                _ = try audioRecorder.startRecording()
                activeRecordingBackend = .whisper
                statusMessage = "Recording with WhisperKit..."
                isRecording = true
            } catch {
                activeRecordingBackend = nil
                statusMessage = "Unable to start Whisper recording: \(error.localizedDescription)"
                isRecording = false
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
            guard let audioURL = audioRecorder.stopRecording() else {
                activeRecordingBackend = nil
                statusMessage = "No Whisper recording was found."
                return
            }
            activeRecordingBackend = nil

            statusMessage = "Transcribing with WhisperKit..."
            isProcessing = true

            Task {
                defer {
                    isProcessing = false
                    refreshWhisperModelStatus()
                }

                do {
                    let text = try await whisperTranscriber.transcribe(audioFileURL: audioURL)
                    transcript = text
                    saveTranscript(text: text, backend: .whisper)
                } catch {
                    statusMessage = "WhisperKit failed: \(error.localizedDescription)"
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
