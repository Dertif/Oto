import AppKit
import Foundation

final class FrontmostApplicationTracker: FrontmostAppProviding {
    private var observer: NSObjectProtocol?

    private(set) var frontmostApplication: NSRunningApplication?

    func start() {
        guard observer == nil else {
            return
        }

        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            frontmostApplication = app
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier != Bundle.main.bundleIdentifier
                else {
                    return
                }
                self?.frontmostApplication = app
            }
        }
    }

    func stop() {
        guard let observer else {
            return
        }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
