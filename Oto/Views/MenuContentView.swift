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
            .disabled(state.isRecording || state.isProcessing)

            Picker("Hotkey Mode", selection: $state.hotkeyMode) {
                ForEach(HotkeyTriggerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hotkey: Fn/Globe")
                    .font(.caption)
                Text(state.hotkeyGuidanceMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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
                    Text("Whisper runtime: \(state.whisperRuntimeStatusLabel)")
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

            if !state.transcriptStableText.isEmpty || !state.transcriptLiveText.isEmpty {
                transcriptView
            }

            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.selectedBackend == .whisper {
                Text(state.whisperLatencySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

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

    private var transcriptView: some View {
        let stable = state.transcriptStableText
        let live = state.transcriptLiveText

        let renderedText: Text = {
            guard !live.isEmpty else {
                return Text(stable)
            }
            let stablePrefix = stable.isEmpty ? "" : "\(stable) "
            return Text("\(stablePrefix)\(Text(live).foregroundStyle(.secondary))")
        }()

        return renderedText
            .font(.caption)
            .lineLimit(4)
    }
}
