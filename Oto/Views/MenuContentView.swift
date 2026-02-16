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
                Text("Accessibility: \(state.accessibilityStatusLabel)")
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

                Button("Request Access") {
                    state.requestAccessibilityPermission()
                }
            }

            Button(state.isRecording ? "Stop Recording" : (state.isProcessing ? "Processing..." : "Start Recording")) {
                state.toggleRecording()
            }
            .disabled(state.isProcessing)

            Toggle("Auto Inject Transcript", isOn: $state.autoInjectEnabled)
                .font(.caption)
                .disabled(state.isRecording || state.isProcessing)

            Toggle("Copy When Auto Inject Off", isOn: $state.copyToClipboardWhenAutoInjectDisabled)
                .font(.caption2)
                .disabled(state.isRecording || state.isProcessing || state.autoInjectEnabled)

            Text("Flow: \(state.reliabilityState.rawValue)")
                .font(.caption)
                .foregroundStyle(reliabilityColor)

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

            if let url = state.lastPrimaryTranscriptURL {
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let url = state.lastFailureContextURL {
                Text("failure-context: \(url.lastPathComponent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if state.debugPanelEnabled {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Run ID: \(state.debugCurrentRunID)")
                        .font(.caption2)
                    Text("Last event: \(state.debugLastEvent)")
                        .font(.caption2)
                    Text("Whisper runtime: \(state.whisperRuntimeStatusLabel)")
                        .font(.caption2)
                    Text("Flags: \(state.debugConfigurationSummary)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Copy Diagnostics Summary") {
                        state.copyDebugSummary()
                    }
                }
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

    private var reliabilityColor: Color {
        switch state.reliabilityState {
        case .ready:
            return .secondary
        case .listening, .transcribing:
            return .primary
        case .injected:
            return .green
        case .failed:
            return .red
        }
    }
}
