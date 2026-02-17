import AppKit
import SwiftUI

@MainActor
final class FloatingOverlayWindowController: NSWindowController {
    private struct StoredOverlayPosition: Codable {
        let normalizedCenterX: Double
        let normalizedMinY: Double
    }

    private enum PositionStore {
        static let key = "oto.overlay.positionsByDisplay"
    }

    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let state: AppState
    private var hasPositionedWindow = false
    private var dragStartOrigin: CGPoint?
    private var windowMoveObserver: NSObjectProtocol?
    private var currentOverlaySize = NSSize(width: 120, height: 46)
    private var currentLayoutMetrics = FloatingOverlayLayoutMetrics(
        size: CGSize(width: 120, height: 46),
        pillCenterY: 23
    )
    private var placement: OverlayPlacement

    init(state: AppState) {
        self.state = state
        placement = state.overlayPlacement

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 120, height: 46)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        super.init(window: panel)
        configureContentView()
        observeWindowMove()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let windowMoveObserver {
            NotificationCenter.default.removeObserver(windowMoveObserver)
        }
    }

    private func configureContentView() {
        guard let panel = window as? OverlayPanel else {
            return
        }

        let rootView = FloatingOverlayView(
            state: state,
            onLayoutChange: { [weak panel, weak self] metrics in
                guard let panel, let self else {
                    return
                }
                self.updateOverlayLayout(metrics, panel: panel)
            },
            onDragChanged: { [weak panel, weak self] translation in
                guard let panel, let self else {
                    return
                }
                self.handleDragChanged(translation: translation, panel: panel)
            },
            onDragEnded: { [weak panel, weak self] in
                guard let panel, let self else {
                    return
                }
                self.handleDragEnded(panel: panel)
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
    }

    func showOverlay() {
        guard let panel = window as? OverlayPanel else {
            return
        }

        if !hasPositionedWindow {
            positionOverlay(panel: panel, forceDefault: false)
            hasPositionedWindow = true
        }
        refreshTooltipDirection(for: panel)
        panel.orderFrontRegardless()
    }

    func hideOverlay() {
        window?.orderOut(nil)
    }

    func applyPlacement(_ placement: OverlayPlacement) {
        self.placement = placement
        guard let panel = window as? OverlayPanel else {
            return
        }

        positionOverlay(panel: panel, forceDefault: false)
        persistPosition(for: panel)
        hasPositionedWindow = true
        OtoLogger.log("Floating overlay placement set to \(placement.rawValue)", category: .flow, level: .info)
    }

    func resetToDefaultPosition() {
        guard let panel = window as? OverlayPanel else {
            return
        }
        clearSavedPositions()
        positionOverlay(panel: panel, forceDefault: true)
        persistPosition(for: panel)
        OtoLogger.log("Floating overlay position reset to default", category: .flow, level: .info)
    }

    private func observeWindowMove() {
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.dragStartOrigin == nil else {
                    return
                }
                self.persistPositionIfPossible()
            }
        }
    }

    private func handleDragChanged(translation: CGSize, panel: NSPanel) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            placement = .custom
        }
        guard let dragStartOrigin else {
            return
        }

        let proposedOrigin = CGPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        )
        panel.setFrameOrigin(clampedOrigin(for: proposedOrigin, panel: panel))
        refreshTooltipDirection(for: panel)
    }

    private func handleDragEnded(panel: NSPanel) {
        dragStartOrigin = nil
        persistPosition(for: panel)
        if state.overlayPlacement != .custom {
            state.overlayPlacement = .custom
        }
        OtoLogger.log("Floating overlay moved to \(panel.frame.origin.debugDescription)", category: .flow, level: .debug)
    }

    private func updateOverlayLayout(_ metrics: FloatingOverlayLayoutMetrics, panel: NSPanel) {
        guard metrics.size.width > 0, metrics.size.height > 0 else {
            return
        }
        guard dragStartOrigin == nil else {
            return
        }

        let targetSize = NSSize(width: ceil(metrics.size.width), height: ceil(metrics.size.height))
        let targetPillCenterY = metrics.pillCenterY
        let sizeChanged = abs(targetSize.width - currentOverlaySize.width) >= 0.5 || abs(targetSize.height - currentOverlaySize.height) >= 0.5
        let pillAnchorChanged = abs(targetPillCenterY - currentLayoutMetrics.pillCenterY) >= 0.5

        if !sizeChanged, !pillAnchorChanged {
            return
        }

        let currentFrame = panel.frame
        let currentPillGlobalY = currentFrame.minY + currentLayoutMetrics.pillCenterY
        let screen = panel.screen ?? screenContaining(point: currentFrame.center) ?? NSScreen.main ?? NSScreen.screens.first
        let anchorCenterX = screen?.frame.midX ?? currentFrame.midX

        let updatedFrame = NSRect(
            x: anchorCenterX - (targetSize.width / 2),
            y: currentPillGlobalY - targetPillCenterY,
            width: targetSize.width,
            height: targetSize.height
        )
        let clamped = clampedFrame(updatedFrame)
        panel.setFrame(clamped, display: true)

        if sizeChanged || pillAnchorChanged {
            OtoLogger.log(
                "Overlay layout update size=\(targetSize.width)x\(targetSize.height) frame=\(clamped.origin.debugDescription) screenMidX=\(anchorCenterX)",
                category: .flow,
                level: .debug
            )
        }

        currentOverlaySize = targetSize
        currentLayoutMetrics = FloatingOverlayLayoutMetrics(size: targetSize, pillCenterY: targetPillCenterY)
        refreshTooltipDirection(for: panel)
    }

    private func positionOverlay(panel: NSPanel, forceDefault: Bool) {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else {
            return
        }

        let targetFrame: NSRect
        if !forceDefault, placement == .custom, let restoredFrame = restoredFrame(for: panel, screen: targetScreen) {
            targetFrame = restoredFrame
        } else {
            targetFrame = frame(for: panel, placement: forceDefault ? .topCenter : placement, screen: targetScreen)
        }

        panel.setFrame(clampedFrame(targetFrame), display: true)
        refreshTooltipDirection(for: panel)
    }

    private func frame(for panel: NSPanel, placement: OverlayPlacement, screen: NSScreen) -> NSRect {
        frame(for: panel.frame.size, placement: placement, screen: screen)
    }

    private func frame(for size: NSSize, placement: OverlayPlacement, screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let topInset: CGFloat = 20
        let sideInset: CGFloat = 16
        let bottomInset: CGFloat = 20

        let originX: CGFloat
        switch placement {
        case .topLeft, .bottomLeft:
            originX = visibleFrame.minX + sideInset
        case .topCenter, .bottomCenter, .custom:
            originX = fullFrame.midX - (size.width / 2)
        case .topRight, .bottomRight:
            originX = visibleFrame.maxX - size.width - sideInset
        }

        let originY: CGFloat
        switch placement {
        case .topLeft, .topCenter, .topRight, .custom:
            originY = visibleFrame.maxY - size.height - topInset
        case .bottomLeft, .bottomCenter, .bottomRight:
            originY = visibleFrame.minY + bottomInset
        }

        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private func restoredFrame(for panel: NSPanel, screen: NSScreen) -> NSRect? {
        guard
            let displayID = displayIdentifier(for: screen),
            let storedPosition = loadStoredPositions()[displayID]
        else {
            return nil
        }

        let visibleFrame = screen.visibleFrame
        let centerX = visibleFrame.minX + (visibleFrame.width * CGFloat(storedPosition.normalizedCenterX))
        let minY = visibleFrame.minY + (visibleFrame.height * CGFloat(storedPosition.normalizedMinY))
        return NSRect(
            x: centerX - (panel.frame.width / 2),
            y: minY,
            width: panel.frame.width,
            height: panel.frame.height
        )
    }

    private func persistPositionIfPossible() {
        guard let panel = window as? NSPanel else {
            return
        }
        persistPosition(for: panel)
    }

    private func persistPosition(for panel: NSPanel) {
        guard
            let screen = screenContaining(point: panel.frame.center) ?? NSScreen.main,
            let displayID = displayIdentifier(for: screen)
        else {
            return
        }

        let visibleFrame = screen.visibleFrame
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return
        }

        let normalizedCenterX = Double((panel.frame.midX - visibleFrame.minX) / visibleFrame.width)
        let normalizedMinY = Double((panel.frame.minY - visibleFrame.minY) / visibleFrame.height)

        var positions = loadStoredPositions()
        positions[displayID] = StoredOverlayPosition(
            normalizedCenterX: min(1, max(0, normalizedCenterX)),
            normalizedMinY: min(1, max(0, normalizedMinY))
        )
        saveStoredPositions(positions)
    }

    private func clearSavedPositions() {
        UserDefaults.standard.removeObject(forKey: PositionStore.key)
    }

    private func loadStoredPositions() -> [String: StoredOverlayPosition] {
        guard
            let data = UserDefaults.standard.data(forKey: PositionStore.key),
            let positions = try? JSONDecoder().decode([String: StoredOverlayPosition].self, from: data)
        else {
            return [:]
        }
        return positions
    }

    private func saveStoredPositions(_ positions: [String: StoredOverlayPosition]) {
        guard let data = try? JSONEncoder().encode(positions) else {
            return
        }
        UserDefaults.standard.set(data, forKey: PositionStore.key)
    }

    private func displayIdentifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.stringValue
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func clampedOrigin(for origin: CGPoint, panel: NSPanel) -> CGPoint {
        let frame = NSRect(origin: origin, size: panel.frame.size)
        let clamped = clampedFrame(frame)
        return clamped.origin
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        let candidateScreen = screenContaining(point: frame.center) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = candidateScreen else {
            return frame
        }

        let visible = screen.visibleFrame
        let fullFrame = screen.frame
        let minX = fullFrame.minX
        let maxX = fullFrame.maxX - frame.width
        let minY = visible.minY
        let maxY = visible.maxY - frame.height

        let clampedX = min(max(frame.origin.x, minX), maxX)
        let clampedY = min(max(frame.origin.y, minY), maxY)
        return NSRect(origin: CGPoint(x: clampedX, y: clampedY), size: frame.size)
    }

    private func refreshTooltipDirection(for panel: NSPanel) {
        let candidateScreen = panel.screen ?? screenContaining(point: panel.frame.center) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = candidateScreen else {
            return
        }

        let visible = screen.visibleFrame
        guard visible.height > 0 else {
            return
        }

        let normalizedCenterY = (panel.frame.midY - visible.minY) / visible.height
        let direction: OverlayTooltipDirection = normalizedCenterY > 0.62 ? .below : .above
        if state.overlayTooltipDirection != direction {
            state.overlayTooltipDirection = direction
        }
    }
}

private extension NSRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
