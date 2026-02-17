import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var state: AppState
    var onOpenAdvancedSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            statusSection

            Divider()
            primaryInteractionSection

            Divider()
            secondaryConfigurationSection

            Divider()
            navigationSection

            Divider()
            Button("Quit Oto") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Oto")
                .font(.headline)
            Spacer()
            Text(state.selectedBackend.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Recorder: \(state.reliabilityState.rawValue)")
                .font(.caption)
                .foregroundStyle(reliabilityColor)
            if shouldShowDetailedStatus {
                Text(state.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var primaryInteractionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(recordingActionLabel) {
                state.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isProcessing)

            Picker("Backend", selection: $state.selectedBackend) {
                ForEach(STTBackend.allCases) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            .pickerStyle(.menu)
            .disabled(state.isRecording || state.isProcessing)

            Picker("Quality", selection: $state.qualityPreset) {
                ForEach(DictationQualityPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .disabled(state.isRecording || state.isProcessing || state.selectedBackend != .whisper)

            Picker("Refinement", selection: $state.refinementMode) {
                ForEach(TextRefinementMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(state.isRecording || state.isProcessing)
        }
    }

    private var secondaryConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Hotkey Mode", selection: $state.hotkeyMode) {
                ForEach(HotkeyTriggerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Toggle("Auto Inject Transcript", isOn: $state.autoInjectEnabled)
                .font(.caption)
                .disabled(state.isRecording || state.isProcessing)

            Toggle("Copy When Auto Inject Off", isOn: $state.copyToClipboardWhenAutoInjectDisabled)
                .font(.caption2)
                .disabled(state.isRecording || state.isProcessing || state.autoInjectEnabled)
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Advanced Settings…") {
                onOpenAdvancedSettings()
            }

            Button("Open Transcripts Folder") {
                state.openTranscriptFolder()
            }
        }
    }

    private var recordingActionLabel: String {
        if state.isRecording {
            return "Stop Recording"
        }

        if state.isProcessing {
            return "Processing…"
        }

        return "Start Recording"
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

    private var shouldShowDetailedStatus: Bool {
        let trimmed = state.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return trimmed.caseInsensitiveCompare(state.reliabilityState.rawValue) != .orderedSame
    }
}
