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
    @Published var micPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcript = ""
    @Published var statusMessage = "Ready"
    @Published var whisperModelStatusLabel = WhisperModelStatus.missing.rawValue
    @Published var lastSavedTranscriptURL: URL?

    private let transcriptStore = TranscriptStore()
    private let appleTranscriber = AppleSpeechTranscriber()
    private let whisperTranscriber = WhisperKitTranscriber()
    private let audioRecorder = AudioFileRecorder()

    init() {
        refreshPermissionStatus()
        refreshWhisperModelStatus()
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
        refreshPermissionStatus()
        refreshWhisperModelStatus()

        guard micPermissionStatus == .authorized else {
            statusMessage = "Microphone access is required."
            return
        }

        transcript = ""

        switch selectedBackend {
        case .appleSpeech:
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
                    statusMessage = "Unable to start: \(error.localizedDescription)"
                    isRecording = false
                    refreshPermissionStatus()
                }
            }

        case .whisper:
            do {
                _ = try audioRecorder.startRecording()
                statusMessage = "Recording with WhisperKit..."
                isRecording = true
            } catch {
                statusMessage = "Unable to start Whisper recording: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    func stopRecording() {
        switch selectedBackend {
        case .appleSpeech:
            appleTranscriber.stop()
            isRecording = false
            statusMessage = "Stopped"
            saveTranscript(text: transcript, backend: .appleSpeech)

        case .whisper:
            isRecording = false
            guard let audioURL = audioRecorder.stopRecording() else {
                statusMessage = "No Whisper recording was found."
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
