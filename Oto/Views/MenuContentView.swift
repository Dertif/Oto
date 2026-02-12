import SwiftUI

struct MenuContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Oto")
                .font(.headline)

            Picker("Model", selection: $state.selectedBackend) {
                ForEach(STTBackend.allCases) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 4) {
                Text("Microphone: \(state.microphoneStatusLabel)")
                    .font(.caption)
                Text("Speech: \(state.speechStatusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.selectedBackend == .whisper {
                    Text("Whisper model: \(state.whisperModelStatusLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Request Mic") {
                    state.requestMicrophonePermission()
                }

                Button("Request Speech") {
                    state.requestSpeechPermission()
                }
            }

            Button(state.isRecording ? "Stop Recording" : (state.isProcessing ? "Processing..." : "Start Recording")) {
                state.toggleRecording()
            }
            .disabled(state.isProcessing)

            if !state.transcript.isEmpty {
                Text(state.transcript)
                    .font(.caption)
                    .lineLimit(3)
            }

            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = state.lastSavedTranscriptURL {
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Open Transcripts Folder") {
                state.openTranscriptFolder()
            }

            Button("Quit Oto") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}
