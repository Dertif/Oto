import SwiftUI
import AppKit
import Combine

@main
struct OtoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.refreshPermissionStatus()
        state.prepareWhisperRuntimeForLaunch()
        statusBarController = StatusBarController(state: state)
    }
}

@MainActor
final class StatusBarController: NSObject {
    private enum RecordingAnimation {
        // Default breathing profile tuned for production UX.
        static let frameInterval: TimeInterval = 0.05
        static let baseCycleDuration: CGFloat = 3.2
        static let minOpacity: CGFloat = 0.5
        static let maxOpacity: CGFloat = 1.0

        // Debug-only runtime tuning (no UI): >1 speeds up, <1 slows down.
        // Example: OTO_DEBUG_RECORDING_ANIMATION_SPEED_MULTIPLIER=1.5
        static let speedMultiplier: CGFloat = {
            let key = "OTO_DEBUG_RECORDING_ANIMATION_SPEED_MULTIPLIER"
            guard
                let raw = ProcessInfo.processInfo.environment[key],
                let value = Double(raw),
                value > 0
            else {
                return 1
            }
            return CGFloat(value)
        }()

        static let cycleDuration: CGFloat = max(0.4, baseCycleDuration / speedMultiplier)
    }

    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let advancedSettingsWindowController: AdvancedSettingsWindowController

    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    private var recordingPhase: CGFloat = 0
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.advancedSettingsWindowController = AdvancedSettingsWindowController(state: state)
        super.init()
        configurePopover()
        configureStatusItem()
        configurePopoverDismissMonitoring()
        observeState()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.applyIcon(for: self.state.visualState)
        }
    }

    deinit {
        recordingTimer?.invalidate()
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(
                state: state,
                onOpenAdvancedSettings: { [weak self] in
                    self?.openAdvancedSettings()
                }
            )
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func observeState() {
        state.$visualState
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.applyIcon(for: newState)
            }
            .store(in: &cancellables)
    }

    private func configurePopoverDismissMonitoring() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleLocalMouseDown(event)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissPopoverIfNeeded()
            }
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard popover.isShown else {
            return
        }

        guard let eventWindow = event.window else {
            if isMouseInsideStatusItemButton() {
                return
            }
            dismissPopoverIfNeeded()
            return
        }

        if eventWindow === popover.contentViewController?.view.window {
            return
        }

        if eventWindow === statusItem.button?.window {
            return
        }

        if isMenuWindow(eventWindow) {
            return
        }

        dismissPopoverIfNeeded()
    }

    private func isMouseInsideStatusItemButton() -> Bool {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window
        else {
            return false
        }

        let mouseInScreen = NSEvent.mouseLocation
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        return buttonFrameInScreen.contains(mouseInScreen)
    }

    private func isMenuWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("NSMenuWindow")
    }

    private func dismissPopoverIfNeeded() {
        guard popover.isShown else {
            return
        }

        popover.performClose(nil)
    }

    private func openAdvancedSettings() {
        dismissPopoverIfNeeded()
        advancedSettingsWindowController.openWindow()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyIcon(for visualState: RecorderVisualState) {
        switch visualState {
        case .idle:
            stopRecordingAnimation()
            setStaticIcon(named: "MenuBarIcon", fallbackSystemSymbol: "mic")
        case .recording:
            setStaticIcon(named: "MenuBarIcon", fallbackSystemSymbol: "mic.fill")
            startRecordingAnimation()
        case .processing:
            stopRecordingAnimation()
            if NSImage(named: "MenuBarIconProcessing") != nil {
                setStaticIcon(named: "MenuBarIconProcessing", fallbackSystemSymbol: "hourglass")
            } else {
                setStaticIcon(named: "MenuBarIcon", fallbackSystemSymbol: "hourglass")
            }
        }
    }

    private func setStaticIcon(named assetName: String, fallbackSystemSymbol: String) {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(named: assetName) {
            image.isTemplate = true
            button.image = image
            button.alphaValue = 1
        } else if let symbol = NSImage(systemSymbolName: fallbackSystemSymbol, accessibilityDescription: nil) {
            symbol.isTemplate = true
            button.image = symbol
            button.alphaValue = 1
        } else {
            button.image = nil
            button.alphaValue = 1
        }
    }

    private func startRecordingAnimation() {
        updateRecordingIconFrame()
        guard recordingTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: RecordingAnimation.frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.recordingPhase += CGFloat(RecordingAnimation.frameInterval) / RecordingAnimation.cycleDuration
                if self.recordingPhase > 1 {
                    self.recordingPhase -= 1
                }
                self.updateRecordingIconFrame()
            }
        }
        recordingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRecordingAnimation() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingPhase = 0
        statusItem.button?.alphaValue = 1
    }

    private func updateRecordingIconFrame() {
        guard let button = statusItem.button else {
            return
        }
        let sine = sin((recordingPhase * .pi * 2) - (.pi / 2))
        let normalized = 0.5 + 0.5 * sine
        let pulseOpacity = RecordingAnimation.minOpacity + normalized * (RecordingAnimation.maxOpacity - RecordingAnimation.minOpacity)
        if abs(button.alphaValue - pulseOpacity) > 0.01 {
            button.alphaValue = pulseOpacity
        }
    }
}
