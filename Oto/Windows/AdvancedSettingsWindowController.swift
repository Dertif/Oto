import AppKit
import SwiftUI

@MainActor
final class AdvancedSettingsWindowController: NSWindowController {
    private var hasPositionedWindow = false

    init(state: AppState) {
        let view = AdvancedSettingsView(state: state)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "Oto Advanced Settings"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("OtoAdvancedSettingsWindow")

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func openWindow() {
        guard let window else {
            return
        }

        if !hasPositionedWindow {
            window.center()
            hasPositionedWindow = true
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
