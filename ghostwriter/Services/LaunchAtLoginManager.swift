//
//  LaunchAtLoginManager.swift
//  ghostwriter
//

import ServiceManagement

/// Registers/unregisters Ghostwriter as a macOS login item via SMAppService
/// (System Settings › General › Login Items).
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    /// Live OS registration state, independent of prefs.toml.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Applies the desired state. Failures are logged and swallowed: the
    /// caller's setting is kept so the menu keeps showing what prefs.toml
    /// asked for until the next reload reconciles it.
    func setEnabled(_ enabled: Bool) {
        // Never touch the user's real login items from the test runner:
        // SMAppService.mainApp would point at the test bundle host app.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }
}
