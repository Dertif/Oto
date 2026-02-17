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

    init(state: AppState) {
        self.state = state

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 120, height: 46)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
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
            onSizeChange: { [weak panel, weak self] size in
                guard let panel, let self else {
                    return
                }
                self.updateOverlaySize(size, panel: panel)
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
        panel.orderFrontRegardless()
    }

    func hideOverlay() {
        window?.orderOut(nil)
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
        }
        guard let dragStartOrigin else {
            return
        }

        let proposedOrigin = CGPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        )
        panel.setFrameOrigin(clampedOrigin(for: proposedOrigin, panel: panel))
    }

    private func handleDragEnded(panel: NSPanel) {
        dragStartOrigin = nil
        persistPosition(for: panel)
        OtoLogger.log("Floating overlay moved to \(panel.frame.origin.debugDescription)", category: .flow, level: .debug)
    }

    private func updateOverlaySize(_ size: CGSize, panel: NSPanel) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        let targetSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        if abs(targetSize.width - currentOverlaySize.width) < 0.5 && abs(targetSize.height - currentOverlaySize.height) < 0.5 {
            return
        }

        currentOverlaySize = targetSize

        let currentFrame = panel.frame
        let updatedFrame = NSRect(
            x: currentFrame.midX - (targetSize.width / 2),
            y: currentFrame.minY,
            width: targetSize.width,
            height: targetSize.height
        )
        panel.setFrame(clampedFrame(updatedFrame), display: true)
    }

    private func positionOverlay(panel: NSPanel, forceDefault: Bool) {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else {
            return
        }

        let frame: NSRect
        if !forceDefault, let restoredFrame = restoredFrame(for: panel, screen: targetScreen) {
            frame = restoredFrame
        } else {
            frame = defaultFrame(for: panel, screen: targetScreen)
        }

        panel.setFrame(clampedFrame(frame), display: true)
    }

    private func defaultFrame(for panel: NSPanel, screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let topInset: CGFloat = 20
        return NSRect(
            x: visibleFrame.midX - (panel.frame.width / 2),
            y: visibleFrame.maxY - panel.frame.height - topInset,
            width: panel.frame.width,
            height: panel.frame.height
        )
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
        let minX = visible.minX
        let maxX = visible.maxX - frame.width
        let minY = visible.minY
        let maxY = visible.maxY - frame.height

        let clampedX = min(max(frame.origin.x, minX), maxX)
        let clampedY = min(max(frame.origin.y, minY), maxY)
        return NSRect(origin: CGPoint(x: clampedX, y: clampedY), size: frame.size)
    }
}

private extension NSRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
