import AppKit
import Foundation

struct StartRecordingRequest {
    let backend: STTBackend
    let microphoneAuthorized: Bool
    let triggerMode: HotkeyTriggerMode
    let permissions: PermissionSnapshot
}

struct StopRecordingRequest {
    let selectedBackend: STTBackend
    let autoInjectEnabled: Bool
    let copyToClipboardWhenAutoInjectDisabled: Bool
    let allowCommandVFallback: Bool
    let triggerMode: HotkeyTriggerMode
    let permissions: PermissionSnapshot
}

struct PermissionSnapshot {
    let microphone: String
    let speech: String
    let accessibility: String

    static let unknown = PermissionSnapshot(
        microphone: "Unknown",
        speech: "Unknown",
        accessibility: "Unknown"
    )
}

@MainActor
final class RecordingFlowCoordinator {
    typealias SnapshotHandler = @MainActor (FlowSnapshot) -> Void

    private enum WhisperCaptureMode {
        case streaming
        case file
    }

    private let speechTranscriber: SpeechTranscribing
    private let whisperTranscriber: WhisperTranscribing
    private let audioRecorder: AudioRecording
    private let transcriptStore: TranscriptPersisting
    private let textInjector: TextInjecting
    private let latencyTracker: WhisperLatencyTracking
    private let latencyRecorder: LatencyMetricsRecording
    private let frontmostAppProvider: FrontmostAppProviding
    private let transcriptNormalizer: TranscriptNormalizer
    private let nowProvider: () -> Date

    private(set) var snapshot: FlowSnapshot {
        didSet {
            onSnapshot?(snapshot)
        }
    }

    var onSnapshot: SnapshotHandler?

    private var activeRecordingBackend: STTBackend?
    private var activeWhisperCaptureMode: WhisperCaptureMode?
    private var activeRecordingStartedAt: Date?
    private var isCaptureStartupInFlight = false
    private var pendingStopRequest: StopRecordingRequest?
    private var currentRunID: String?
    private var latestPermissionSnapshot: PermissionSnapshot = .unknown
    private var latestHotkeyMode: HotkeyTriggerMode = .hold
    private var latestAutoInjectEnabled = true
    private var latestAllowCommandVFallback = false
    private var latestInjectionDiagnostics: TextInjectionDiagnostics?
    private var appleRunStartedAt: Date?
    private var appleFirstPartialAt: Date?
    private var appleStopRequestedAt: Date?

    init(
        speechTranscriber: SpeechTranscribing,
        whisperTranscriber: WhisperTranscribing,
        audioRecorder: AudioRecording,
        transcriptStore: TranscriptPersisting,
        textInjector: TextInjecting,
        latencyTracker: WhisperLatencyTracking,
        latencyRecorder: LatencyMetricsRecording,
        frontmostAppProvider: FrontmostAppProviding,
        transcriptNormalizer: TranscriptNormalizer = .shared,
        nowProvider: @escaping () -> Date = Date.init,
        initialSnapshot: FlowSnapshot = .initial
    ) {
        self.speechTranscriber = speechTranscriber
        self.whisperTranscriber = whisperTranscriber
        self.audioRecorder = audioRecorder
        self.transcriptStore = transcriptStore
        self.textInjector = textInjector
        self.latencyTracker = latencyTracker
        self.latencyRecorder = latencyRecorder
        self.frontmostAppProvider = frontmostAppProvider
        self.transcriptNormalizer = transcriptNormalizer
        self.nowProvider = nowProvider
        snapshot = initialSnapshot
        snapshot.latencySummary = latencyRecorder.summary()
    }

    func requestPermissionsRefresh(permissions: PermissionSnapshot? = nil, hotkeyMode: HotkeyTriggerMode? = nil) {
        if let permissions {
            latestPermissionSnapshot = permissions
        }
        if let hotkeyMode {
            latestHotkeyMode = hotkeyMode
        }
        onSnapshot?(snapshot)
    }

    func startRecording(request: StartRecordingRequest) {
        guard snapshot.phase != .listening, snapshot.phase != .transcribing, snapshot.phase != .injecting else {
            OtoLogger.log("Ignored start request while phase=\(snapshot.phase)", category: .flow, level: .debug)
            return
        }

        if snapshot.phase == .failed || snapshot.phase == .completed {
            currentRunID = nil
            setRunID(nil)
            transition(.resetToIdle(message: "Ready"))
        }

        latestPermissionSnapshot = request.permissions
        latestHotkeyMode = request.triggerMode
        latestAutoInjectEnabled = true
        latestAllowCommandVFallback = false
        latestInjectionDiagnostics = nil
        appleRunStartedAt = nil
        appleFirstPartialAt = nil
        appleStopRequestedAt = nil

        let runID = Self.makeRunID()
        currentRunID = runID
        setRunID(runID)
        logFlow(
            "Start requested backend=\(request.backend.rawValue), triggerMode=\(request.triggerMode.rawValue), micAuthorized=\(request.microphoneAuthorized)"
        )

        isCaptureStartupInFlight = true
        pendingStopRequest = nil
        transition(.startRequested(backend: request.backend, message: startMessage(for: request.backend)))

        guard request.microphoneAuthorized else {
            isCaptureStartupInFlight = false
            pendingStopRequest = nil
            logFlow("Start failed: microphone access is required", level: .error)
            transition(.captureFailed(message: "Microphone access is required."))
            return
        }

        switch request.backend {
        case .appleSpeech:
            activeRecordingBackend = .appleSpeech
            Task {
                do {
                    try await speechTranscriber.start(
                        onUpdate: { [weak self] text, _ in
                            guard let self else {
                                return
                            }
                            let normalizedText = self.transcriptNormalizer.normalize(text)
                            if self.appleFirstPartialAt == nil, !normalizedText.isEmpty {
                                self.appleFirstPartialAt = self.nowProvider()
                            }
                            self.transition(.transcriptionProgress(stable: normalizedText, live: ""))
                        },
                        onError: { [weak self] message in
                            guard let self else {
                                return
                            }
                            guard self.snapshot.phase == .listening || self.snapshot.phase == .transcribing || self.snapshot.phase == .injecting else {
                                return
                            }
                            self.activeRecordingBackend = nil
                            self.activeRecordingStartedAt = nil
                            self.appleRunStartedAt = nil
                            self.appleFirstPartialAt = nil
                            self.appleStopRequestedAt = nil
                            self.isCaptureStartupInFlight = false
                            self.pendingStopRequest = nil
                            self.logFlow("Apple Speech error: \(message)", level: .error)
                            self.transition(.captureFailed(message: "Speech error: \(message)"))
                        }
                    )
                    guard self.snapshot.phase == .listening, self.activeRecordingBackend == .appleSpeech else {
                        return
                    }
                    activeRecordingStartedAt = nowProvider()
                    appleRunStartedAt = activeRecordingStartedAt
                    isCaptureStartupInFlight = false
                    logFlow("Apple Speech capture started")
                    flushPendingStopRequestIfNeeded()
                } catch {
                    guard self.snapshot.phase == .listening, self.activeRecordingBackend == .appleSpeech else {
                        return
                    }
                    activeRecordingBackend = nil
                    activeRecordingStartedAt = nil
                    appleRunStartedAt = nil
                    appleFirstPartialAt = nil
                    appleStopRequestedAt = nil
                    isCaptureStartupInFlight = false
                    pendingStopRequest = nil
                    logFlow("Apple Speech start failed: \(error.localizedDescription)", level: .error)
                    transition(.captureFailed(message: "Unable to start: \(error.localizedDescription)"))
                }
            }

        case .whisper:
            activeRecordingBackend = .whisper
            Task {
                do {
                    try await startWhisperCapture()
                    guard self.snapshot.phase == .listening, self.activeRecordingBackend == .whisper else {
                        return
                    }
                    activeRecordingStartedAt = nowProvider()
                    setStatus(startMessage(for: .whisper))
                    isCaptureStartupInFlight = false
                    logFlow("Whisper capture started")
                    flushPendingStopRequestIfNeeded()
                } catch {
                    guard self.snapshot.phase == .listening, self.activeRecordingBackend == .whisper else {
                        return
                    }
                    activeRecordingBackend = nil
                    activeWhisperCaptureMode = nil
                    activeRecordingStartedAt = nil
                    isCaptureStartupInFlight = false
                    pendingStopRequest = nil
                    latencyTracker.reset()
                    logFlow("Whisper capture start failed: \(error.localizedDescription)", level: .error)
                    transition(.captureFailed(message: "Unable to start Whisper recording: \(error.localizedDescription)"))
                }
            }
        }
    }

    func stopRecording(request: StopRecordingRequest) {
        guard snapshot.phase == .listening else {
            OtoLogger.log("Ignored stop request while phase=\(snapshot.phase)", category: .flow, level: .debug)
            return
        }

        latestHotkeyMode = request.triggerMode
        latestPermissionSnapshot = request.permissions
        latestAutoInjectEnabled = request.autoInjectEnabled
        latestAllowCommandVFallback = request.allowCommandVFallback

        if isCaptureStartupInFlight || activeRecordingStartedAt == nil {
            pendingStopRequest = request
            logFlow("Deferring stop until startup completes")
            return
        }

        let backendToStop = activeRecordingBackend ?? request.selectedBackend
        let stopRequestedAt = nowProvider()
        let recordingDuration = activeRecordingStartedAt.map { nowProvider().timeIntervalSince($0) } ?? 0
        activeRecordingStartedAt = nil
        if backendToStop == .appleSpeech {
            appleStopRequestedAt = stopRequestedAt
        }
        logFlow("Stop requested backend=\(backendToStop.rawValue), duration=\(String(format: "%.2f", recordingDuration))s")

        if recordingDuration > 0, recordingDuration < 0.2 {
            handleShortCapture(backend: backendToStop)
            return
        }

        switch backendToStop {
        case .appleSpeech:
            activeRecordingBackend = nil
            transition(.stopRequested(message: "Transcribing with Apple Speech..."))

            Task {
                defer {
                    self.finalizeAppleLatencyRun()
                }
                let finalizedText = await speechTranscriber.stopAndFinalize(timeout: 0.75)
                let trimmed = self.transcriptNormalizer.normalize(finalizedText)

                guard !trimmed.isEmpty else {
                    await self.persistFailureContext(backend: .appleSpeech, reason: "No speech detected")
                    self.logFlow("Apple Speech finalization produced empty transcript", level: .error)
                    self.transition(.transcriptionFailed(message: "Apple Speech failed: no speech detected."))
                    return
                }

                await self.handleFinalTranscript(
                    text: trimmed,
                    backend: .appleSpeech,
                    autoInjectEnabled: request.autoInjectEnabled,
                    copyToClipboardWhenAutoInjectDisabled: request.copyToClipboardWhenAutoInjectDisabled,
                    allowCommandVFallback: request.allowCommandVFallback
                )
            }

        case .whisper:
            activeRecordingBackend = nil
            latencyTracker.markStopRequested(at: nowProvider())
            transition(.stopRequested(message: "Transcribing with WhisperKit..."))

            let captureMode = activeWhisperCaptureMode
            activeWhisperCaptureMode = nil
            let audioURL = captureMode == .file ? audioRecorder.stopRecording() : nil

            Task {
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

                    await self.handleFinalTranscript(
                        text: text,
                        backend: .whisper,
                        autoInjectEnabled: request.autoInjectEnabled,
                        copyToClipboardWhenAutoInjectDisabled: request.copyToClipboardWhenAutoInjectDisabled,
                        allowCommandVFallback: request.allowCommandVFallback
                    )
                } catch {
                    await self.persistFailureContext(backend: .whisper, reason: error.localizedDescription)
                    self.logFlow("Whisper finalization failed: \(error.localizedDescription)", level: .error)
                    self.transition(.transcriptionFailed(message: "WhisperKit failed: \(error.localizedDescription)"))
                }

                self.finalizeWhisperLatencyRun()
            }
        }
    }

    private func handleShortCapture(backend: STTBackend) {
        logFlow("Capture too short for backend=\(backend.rawValue)", level: .info)
        switch backend {
        case .appleSpeech:
            speechTranscriber.stop()
        case .whisper:
            if activeWhisperCaptureMode == .streaming {
                Task {
                    _ = try? await whisperTranscriber.stopStreamingAndFinalize()
                }
            } else {
                _ = audioRecorder.stopRecording()
            }
            activeWhisperCaptureMode = nil
        }

        activeRecordingBackend = nil
        appleRunStartedAt = nil
        appleFirstPartialAt = nil
        appleStopRequestedAt = nil
        Task {
            await self.persistFailureContext(backend: backend, reason: "Capture was too short")
            self.transition(.captureTooShort(message: "Capture was too short. Hold slightly longer and retry."))
        }
    }

    private func handleFinalTranscript(
        text: String,
        backend: STTBackend,
        autoInjectEnabled: Bool,
        copyToClipboardWhenAutoInjectDisabled: Bool,
        allowCommandVFallback: Bool
    ) async {
        let trimmed = transcriptNormalizer.normalize(text)
        guard !trimmed.isEmpty else {
            await persistFailureContext(backend: backend, reason: "Empty transcription")
            logFlow("\(backend.rawValue) final transcript empty", level: .error)
            transition(.transcriptionFailed(message: "\(backend.rawValue) failed: empty transcription."))
            return
        }

        logFlow("Transcription succeeded backend=\(backend.rawValue), charCount=\(trimmed.count)")
        transition(.transcriptionSucceeded(text: trimmed))

        var transcriptSaveErrorMessage: String?
        do {
            let savedURL = try transcriptStore.save(text: trimmed, backend: backend)
            setPrimaryTranscriptURL(savedURL)
            OtoLogger.log("Saved transcript artifact: \(savedURL.lastPathComponent)", category: .artifacts, level: .info)
        } catch {
            let message = "Failed to save transcript: \(error.localizedDescription)"
            transcriptSaveErrorMessage = message
            setStatus(message)
            OtoLogger.log(message, category: .artifacts, level: .error)
        }

        guard autoInjectEnabled else {
            let clipboardCopied = copyToClipboardWhenAutoInjectDisabled ? copyTranscriptToClipboard(trimmed) : false
            let message: String
            if let transcriptSaveErrorMessage {
                if copyToClipboardWhenAutoInjectDisabled {
                    message = clipboardCopied
                        ? "\(transcriptSaveErrorMessage) Copied transcript to clipboard."
                        : "\(transcriptSaveErrorMessage) Clipboard copy failed."
                } else {
                    message = "\(transcriptSaveErrorMessage) Auto-inject disabled; transcript not copied to clipboard."
                }
            } else {
                if copyToClipboardWhenAutoInjectDisabled {
                    message = clipboardCopied
                        ? "Saved transcript and copied to clipboard."
                        : "Saved transcript; clipboard copy failed."
                } else {
                    message = "Saved transcript (auto-inject disabled)."
                }
            }
            logFlow(
                "Injection skipped by configuration (copyWhenAutoInjectOff=\(copyToClipboardWhenAutoInjectDisabled), copiedToClipboard=\(clipboardCopied))"
            )
            transition(.injectionSkipped(message: message))
            return
        }

        transition(.injectionStarted)
        latestInjectionDiagnostics = nil

        let preferredApp = frontmostAppProvider.frontmostApplication
        let preferredBundleID = preferredApp?.bundleIdentifier ?? "unknown"
        OtoLogger.log("Injecting transcript into app=\(preferredBundleID)", category: .injection, level: .info)
        let injectionReport = await textInjector.inject(request: TextInjectionRequest(
            text: trimmed,
            preferredApplication: preferredApp,
            allowCommandVFallback: allowCommandVFallback
        ))
        latestInjectionDiagnostics = injectionReport.diagnostics

        if let outcome = injectionReport.outcome {
            switch outcome {
            case .success:
                OtoLogger.log("Text injection succeeded", category: .injection, level: .info)
                transition(.injectionSucceeded(
                    message: transcriptSaveErrorMessage.map { "Injected transcript into focused app. \($0)" } ?? "Injected transcript into focused app."
                ))
            case let .successWithWarning(warning):
                await persistFailureContext(
                    backend: backend,
                    reason: "Injection warning: \(warning)",
                    injectionDiagnostics: injectionReport.diagnostics
                )
                OtoLogger.log("Text injection succeeded with warning: \(warning)", category: .injection, level: .info)
                transition(.injectionSucceeded(
                    message: transcriptSaveErrorMessage.map { "Injected transcript with warning: \(warning). \($0)" } ?? "Injected transcript with warning: \(warning)"
                ))
            }
            return
        }

        if let error = injectionReport.error {
            await persistFailureContext(
                backend: backend,
                reason: error.localizedDescription,
                injectionDiagnostics: injectionReport.diagnostics
            )
            OtoLogger.log("Text injection failed: \(error.localizedDescription)", category: .injection, level: .error)
            let failureMessage = transcriptSaveErrorMessage.map {
                "Injection failed: \(error.localizedDescription). \($0)"
            } ?? "Injection failed: \(error.localizedDescription)"
            transition(.injectionFailed(message: failureMessage))
            return
        }

        await persistFailureContext(
            backend: backend,
            reason: "Unknown injection failure",
            injectionDiagnostics: injectionReport.diagnostics
        )
        transition(.injectionFailed(message: "Injection failed: unknown error"))
    }

    private func flushPendingStopRequestIfNeeded() {
        guard !isCaptureStartupInFlight, let pendingStopRequest, snapshot.phase == .listening else {
            return
        }
        self.pendingStopRequest = nil
        logFlow("Flushing deferred stop request")
        stopRecording(request: pendingStopRequest)
    }

    private func persistFailureContext(
        backend: STTBackend,
        reason: String,
        injectionDiagnostics: TextInjectionDiagnostics? = nil
    ) async {
        let partialText = snapshot.transcriptStableText.trimmingCharacters(in: .whitespacesAndNewlines)
        let frontmostBundleID = frontmostAppProvider.frontmostApplication?.bundleIdentifier ?? "Unknown"
        let runID = currentRunID ?? "Unknown"
        let lastEvent = snapshot.lastEvent.map { "\($0)" } ?? "None"
        let diagnostics = injectionDiagnostics ?? latestInjectionDiagnostics

        let strategyChain = diagnostics?.strategyChain.map(\.rawValue).joined(separator: " -> ") ?? "None"
        let attempts = (diagnostics?.attempts ?? []).map {
            "\($0.strategy.rawValue):\($0.result.rawValue)\($0.reason.map { "(\($0))" } ?? "")"
        }.joined(separator: ", ")
        let finalStrategy = diagnostics?.finalStrategy?.rawValue ?? "None"
        let focusedRole = diagnostics?.focusedRole ?? "Unknown"
        let focusedSubrole = diagnostics?.focusedSubrole ?? "Unknown"
        let focusWaitMs = diagnostics?.focusWaitMilliseconds ?? 0
        let preferredBundleID = diagnostics?.preferredAppBundleID ?? "Unknown"
        let preferredActivated = diagnostics?.preferredAppActivated ?? false
        let diagnosticsFrontmostBundleID = diagnostics?.frontmostAppBundleID ?? frontmostBundleID

        let contextText = """
        [failure-context]
        run_id: \(runID)
        timestamp: \(nowProvider().ISO8601Format())
        backend: \(backend.rawValue)
        phase: \(snapshot.phase)
        last_event: \(lastEvent)
        reason: \(reason)
        hotkey_mode: \(latestHotkeyMode.rawValue)
        auto_inject_enabled: \(latestAutoInjectEnabled)
        allow_command_v_fallback: \(latestAllowCommandVFallback)
        microphone_permission: \(latestPermissionSnapshot.microphone)
        speech_permission: \(latestPermissionSnapshot.speech)
        accessibility_permission: \(latestPermissionSnapshot.accessibility)
        whisper_runtime_status: \(whisperTranscriber.runtimeStatusLabel)
        frontmost_app_bundle_id: \(frontmostBundleID)
        preferred_app_bundle_id: \(preferredBundleID)
        preferred_app_activated: \(preferredActivated)
        injection_strategy_chain: \(strategyChain)
        injection_attempts: \(attempts.isEmpty ? "None" : attempts)
        injection_final_strategy: \(finalStrategy)
        focused_role: \(focusedRole)
        focused_subrole: \(focusedSubrole)
        focus_wait_ms: \(focusWaitMs)
        frontmost_app_bundle_id_during_injection: \(diagnosticsFrontmostBundleID)

        \(partialText)
        """

        if let savedURL = try? transcriptStore.save(text: contextText, backend: backend, prefix: "failure-context") {
            setFailureContextURL(savedURL)
            OtoLogger.log("Saved failure-context artifact: \(savedURL.lastPathComponent)", category: .artifacts, level: .info)
        } else {
            OtoLogger.log("Failed to save failure-context artifact", category: .artifacts, level: .error)
        }
    }

    private func transition(_ event: FlowEvent) {
        snapshot = FlowReducer.reduce(snapshot: snapshot, event: event)
    }

    private func setStatus(_ message: String) {
        var next = snapshot
        next.statusMessage = message
        snapshot = next
    }

    private func setRunID(_ runID: String?) {
        var next = snapshot
        next.runID = runID
        snapshot = next
    }

    private func setPrimaryTranscriptURL(_ url: URL) {
        var next = snapshot
        next.artifacts.primaryURL = url
        snapshot = next
    }

    private func setFailureContextURL(_ url: URL) {
        var next = snapshot
        next.artifacts.failureContextURL = url
        snapshot = next
    }

    private func setLatencySummary(_ summary: String) {
        var next = snapshot
        next.latencySummary = summary
        snapshot = next
    }

    private func finalizeAppleLatencyRun() {
        guard let startedAt = appleRunStartedAt else {
            return
        }

        let completedAt = nowProvider()
        let metrics = BackendLatencyMetrics(
            backend: .appleSpeech,
            usedStreaming: true,
            timeToFirstPartial: appleFirstPartialAt.map { $0.timeIntervalSince(startedAt) },
            stopToFinal: appleStopRequestedAt.map { completedAt.timeIntervalSince($0) },
            total: completedAt.timeIntervalSince(startedAt),
            recordedAt: completedAt
        )

        latencyRecorder.record(metrics)
        setLatencySummary(latencyRecorder.summary())
        OtoLogger.log("[run:\(currentRunID ?? "Unknown")] \(metrics.runSummary)", category: .speech, level: .info)

        appleRunStartedAt = nil
        appleFirstPartialAt = nil
        appleStopRequestedAt = nil
    }

    private func copyTranscriptToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        OtoLogger.log("Copied transcript to clipboard: \(copied)", category: .artifacts, level: copied ? .info : .error)
        return copied
    }

    private func startMessage(for backend: STTBackend) -> String {
        switch backend {
        case .appleSpeech:
            return "Listening with Apple Speech..."
        case .whisper:
            return "Listening with WhisperKit..."
        }
    }

    private func startWhisperCapture() async throws {
        if whisperTranscriber.streamingEnabled {
            logFlow("Starting Whisper in streaming mode")
            try await startWhisperStreamingCapture()
            return
        }

        logFlow("Starting Whisper in file mode")
        try startWhisperFileCapture()
    }

    private func startWhisperStreamingCapture() async throws {
        latencyTracker.beginRun(usingStreaming: true, at: nowProvider())
        activeWhisperCaptureMode = .streaming

        do {
            try await whisperTranscriber.startStreaming { [weak self] partial in
                guard let self else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    self.transition(.transcriptionProgress(stable: partial.stableText, live: partial.liveText))
                    if !partial.combinedText.isEmpty {
                        self.latencyTracker.markFirstPartial(at: self.nowProvider())
                    }
                }
            }
        } catch {
            latencyTracker.reset()
            logFlow("Whisper streaming unavailable, falling back to file mode", level: .info)
            try startWhisperFileCapture()
        }
    }

    private func startWhisperFileCapture() throws {
        _ = try audioRecorder.startRecording()
        latencyTracker.beginRun(usingStreaming: false, at: nowProvider())
        activeWhisperCaptureMode = .file
    }

    private func finalizeWhisperLatencyRun() {
        guard let metrics = latencyTracker.finish(at: nowProvider()) else {
            return
        }

        let backendMetrics = BackendLatencyMetrics(
            backend: .whisper,
            usedStreaming: metrics.usedStreaming,
            timeToFirstPartial: metrics.timeToFirstPartial,
            stopToFinal: metrics.stopToFinalTranscript,
            total: metrics.totalDuration,
            recordedAt: nowProvider()
        )
        latencyRecorder.record(backendMetrics)
        setLatencySummary(latencyRecorder.summary())

        OtoLogger.log("[run:\(currentRunID ?? "Unknown")] \(backendMetrics.runSummary)", category: .whisper, level: .info)
    }

    private func logFlow(_ message: String, level: OtoLogLevel = .info) {
        OtoLogger.log("[run:\(currentRunID ?? "Unknown")] \(message)", category: .flow, level: level)
    }

    private static func makeRunID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}
