//
//  ghostwriterApp.swift
//  ghostwriter
//

import SwiftUI
import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Piping prompts to a child's stdin must never kill us via SIGPIPE when
        // the child exits without reading (EPIPE is handled at the write site).
        signal(SIGPIPE, SIG_IGN)

        // Know the frontmost app from the very first launch (paste target)
        ActiveAppTracker.shared.start()

        // Setup Menu Bar status item
        MenuBarManager.shared.setup()

        // Setup Floating popover window
        FloatingWindowManager.shared.setup()

        // Register global hotkey from preferences
        HotKeyManager.shared.onHotKeyPressed = {
            FloatingWindowManager.shared.toggle()
        }
        HotKeyManager.shared.register(shortcut: AppSettings.shared.shortcut)

        // Caret placement and the synthetic ⌘V both need Accessibility;
        // prompt for it once if it is missing.
        TextInserter.requestAccessibilityPermissionIfNeeded()
    }
}

@main
struct ghostwriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
