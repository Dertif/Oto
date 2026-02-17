import AppKit
import SwiftUI

private enum AdvancedSettingsSection: String, CaseIterable, Identifiable {
    case settings
    case transcripts
    case diagnostics
    case extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings:
            return "Settings"
        case .transcripts:
            return "Transcripts"
        case .diagnostics:
            return "Diagnostics"
        case .extensions:
            return "Extensions"
        }
    }

    var symbolName: String {
        switch self {
        case .settings:
            return "slider.horizontal.3"
        case .transcripts:
            return "text.bubble"
        case .diagnostics:
            return "waveform.path.ecg"
        case .extensions:
            return "sparkles"
        }
    }

    var sidebarHint: String {
        switch self {
        case .settings:
            return "Dictation, permissions, output"
        case .transcripts:
            return "History, copy, review"
        case .diagnostics:
            return "Flow, latency, runtime"
        case .extensions:
            return "Future advanced capabilities"
        }
    }

    var summary: String {
        switch self {
        case .settings:
            return "Primary dictation controls, system permissions, and transcript delivery behavior."
        case .transcripts:
            return "Browse saved transcript artifacts and quickly copy content."
        case .diagnostics:
            return "Operational context for debugging latency and run outcomes."
        case .extensions:
            return "Reserved area for future advanced features without reshaping navigation."
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var state: AppState
    @State private var selection: AdvancedSettingsSection? = .settings
    @State private var hasLoadedTranscripts = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AdvancedSettingsSection.allCases) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(section.title, systemImage: section.symbolName)
                        Text(section.sidebarHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader
                    sectionBody
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(28)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 280)
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            refreshTranscriptsIfNeeded(for: activeSection)
        }
        .onChange(of: selection) { _, newValue in
            refreshTranscriptsIfNeeded(for: newValue ?? .settings)
        }
    }

    private var activeSection: AdvancedSettingsSection {
        selection ?? .settings
    }

    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activeSection.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(activeSection.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(activeSection.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch activeSection {
        case .settings:
            settingsSection
        case .transcripts:
            transcriptsSection
        case .diagnostics:
            diagnosticsSection
        case .extensions:
            extensionsSection
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Dictation",
                subtitle: "Recognition backend, quality, and refinement behavior."
            ) {
                InlineControlRow(label: "Backend") {
                    Picker("Backend", selection: $state.selectedBackend) {
                        ForEach(STTBackend.allCases) { backend in
                            Text(backend.rawValue).tag(backend)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .disabled(state.isRecording || state.isProcessing)
                }

                InlineControlRow(label: "Quality") {
                    Picker("Quality Preset", selection: $state.qualityPreset) {
                        ForEach(DictationQualityPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .disabled(state.isRecording || state.isProcessing || state.selectedBackend != .whisper)
                } helpText: {
                    state.selectedBackend == .whisper
                        ? state.qualityPreset.description
                        : "Quality preset applies to WhisperKit only."
                }

                InlineControlRow(label: "Refinement") {
                    Picker("Refinement Mode", selection: $state.refinementMode) {
                        ForEach(TextRefinementMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .disabled(state.isRecording || state.isProcessing)
                } helpText: {
                    state.refinementMode.description
                }
            }

            SettingsCard(
                title: "Hotkey",
                subtitle: "Trigger behavior for Fn/Globe capture."
            ) {
                InlineControlRow(label: "Trigger Mode") {
                    Picker("Trigger Mode", selection: $state.hotkeyMode) {
                        ForEach(HotkeyTriggerMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                }

                Text("Key: Fn/Globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.hotkeyGuidanceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(
                title: "System Access",
                subtitle: "Permissions required for dictation and injection."
            ) {
                PermissionRow(
                    title: "Microphone",
                    value: state.microphoneStatusLabel,
                    action: { state.requestMicrophonePermission() },
                    showAction: state.micPermissionStatus != .authorized
                ) {
                    Text("Request Access")
                }

                PermissionRow(
                    title: "Speech",
                    value: state.speechStatusLabel,
                    action: { state.requestSpeechPermission() },
                    showAction: state.speechPermissionStatus != .authorized
                ) {
                    Text("Request Access")
                }

                PermissionRow(
                    title: "Accessibility",
                    value: state.accessibilityStatusLabel,
                    action: { state.requestAccessibilityPermission() },
                    showAction: !state.accessibilityTrusted
                ) {
                    Text("Request Access")
                }

                if state.selectedBackend == .whisper {
                    Divider()
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Whisper model")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(state.whisperModelStatusLabel)
                                .font(.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Whisper runtime")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(state.whisperRuntimeStatusLabel)
                                .font(.subheadline)
                        }
                    }
                }
            }

            SettingsCard(
                title: "Output Delivery",
                subtitle: "What happens after transcription finalizes."
            ) {
                Toggle("Auto Inject Transcript", isOn: $state.autoInjectEnabled)
                    .disabled(state.isRecording || state.isProcessing)

                Toggle("Copy When Auto Inject Off", isOn: $state.copyToClipboardWhenAutoInjectDisabled)
                    .disabled(state.isRecording || state.isProcessing || state.autoInjectEnabled)

                Toggle("Allow Cmd+V Fallback (may use clipboard)", isOn: $state.allowCommandVFallback)
                    .disabled(state.isRecording || state.isProcessing)
            }
        }
    }

    private var transcriptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Transcript History",
                subtitle: "Most recent transcript artifacts first."
            ) {
                HStack {
                    Text("\(state.transcriptHistoryEntries.count) item\(state.transcriptHistoryEntries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button("Refresh") {
                        state.refreshTranscriptHistory()
                        hasLoadedTranscripts = true
                    }
                    .buttonStyle(.bordered)
                }

                if let error = state.transcriptHistoryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                }

                if state.transcriptHistoryEntries.isEmpty {
                    Text("No transcripts found yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(state.transcriptHistoryEntries) { entry in
                            TranscriptHistoryCard(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Flow Health",
                subtitle: "Current runtime state and latency snapshots."
            ) {
                metricRow(label: "State", value: state.reliabilityState.rawValue)
                metricRow(label: "Status", value: state.statusMessage)
                metricRow(label: "Latency", value: state.latencySummary)
                metricRow(label: "Refinement", value: state.refinementLatencySummary)
                metricRow(label: "Output Source", value: state.lastOutputSourceLabel)
            }

            SettingsCard(
                title: "Actions",
                subtitle: "Open transcript folder and export current diagnostics."
            ) {
                HStack(spacing: 8) {
                    Button("Open Transcripts Folder") {
                        state.openTranscriptFolder()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Diagnostics Summary") {
                        state.copyDebugSummary()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if state.debugPanelEnabled {
                SettingsCard(
                    title: "Debug",
                    subtitle: "Runtime identifiers and current debug flags."
                ) {
                    metricRow(label: "Run ID", value: state.debugCurrentRunID)
                    metricRow(label: "Last Event", value: state.debugLastEvent)
                    metricRow(label: "Flags", value: state.debugConfigurationSummary)
                }
            }
        }
    }

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Scalability Note",
                subtitle: nil
            ) {
                Text("This window is intentionally scalable.")
                    .font(.headline)
                Text("Add new advanced sections in the sidebar instead of expanding menu bar complexity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(
                title: "Integration Placeholder",
                subtitle: nil
            ) {
                Text("Reserve this space for future advanced behavior that should remain outside Phase 0.4 scope until explicitly approved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshTranscriptsIfNeeded(for section: AdvancedSettingsSection) {
        guard section == .transcripts else {
            return
        }
        guard !hasLoadedTranscripts else {
            return
        }
        state.refreshTranscriptHistory()
        hasLoadedTranscripts = true
    }

    @ViewBuilder
    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct InlineControlRow<Control: View>: View {
    let label: String
    let control: () -> Control
    let helpText: (() -> String)?

    init(
        label: String,
        @ViewBuilder control: @escaping () -> Control,
        helpText: (() -> String)? = nil
    ) {
        self.label = label
        self.control = control
        self.helpText = helpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.subheadline)
                Spacer(minLength: 6)
                control()
                    .labelsHidden()
            }

            if let help = helpText?() {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionRow<ButtonTitle: View>: View {
    let title: String
    let value: String
    let action: () -> Void
    let showAction: Bool
    @ViewBuilder var buttonTitle: () -> ButtonTitle

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                statusPill
            }

            Spacer(minLength: 8)

            if showAction {
                Button(action: action, label: buttonTitle)
                    .buttonStyle(.bordered)
            } else {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var statusPill: some View {
        Text(value)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.14), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        let normalized = value.lowercased()
        if normalized.contains("authorized") {
            return .green
        }
        if normalized.contains("denied") || normalized.contains("restricted") {
            return .red
        }
        return .secondary
    }
}

private struct TranscriptHistoryCard: View {
    let entry: TranscriptHistoryEntry

    @State private var isExpanded = false
    @State private var didCopy = false
    @State private var resetCopyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.timestampFormatter.string(from: entry.timestamp))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(entry.kind.title)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)

                Text(entry.backendLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(action: copyTranscript) {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            Toggle("Enhanced", isOn: .constant(entry.isEnhanced))
                .disabled(true)
                .toggleStyle(.switch)

            Text(entry.textBody)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 10)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.lineCount > 10 {
                Button(isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onDisappear {
            resetCopyTask?.cancel()
        }
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.textBody, forType: .string)
        didCopy = true
        resetCopyTask?.cancel()
        resetCopyTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                didCopy = false
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
