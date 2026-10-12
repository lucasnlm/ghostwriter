//
//  ActiveAppTracker.swift
//  ghostwriter
//

import AppKit

final class ActiveAppTracker {
    static let shared = ActiveAppTracker()

    private var activationObserver: NSObjectProtocol?

    private(set) var previousApp: NSRunningApplication?

    /// Starts tracking: captures the current frontmost app and follows
    /// activation changes so a valid paste target is always known — including
    /// when the popup is first opened from the menu bar, where Ghostwriter is
    /// already frontmost by the time `show()` runs.
    func start() {
        guard activationObserver == nil else { return }
        captureCurrentApp()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                self?.record(app)
            }
        }
    }

    func captureCurrentApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            record(frontApp)
        }
    }

    private func record(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApp = app
    }

    func reactivatePreviousApp() {
        guard let app = previousApp, !app.isTerminated else { return }
        _ = app.activate()
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }
}
