//
//  MenuBarManager.swift
//  ghostwriter
//

import AppKit

final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    
    func setup() {
        if statusItem != nil { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: AppStrings.General.appName)
        image?.isTemplate = true
        button.image = image
        
        let menu = NSMenu()
        menu.delegate = self
        
        let showTitle = AppStrings.Actions.showWindow(hotkey: HotKeyManager.shared.displayString)
        let showItem = NSMenuItem(title: showTitle, action: #selector(showGhostwriter), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: AppStrings.Actions.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launchAtLoginItem = NSMenuItem(title: AppStrings.Actions.launchAtLogin, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: AppStrings.Actions.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    func updateShortcutTitle(_ displayString: String, registrationFailed: Bool = false) {
        guard let menu = statusItem?.menu, let firstItem = menu.items.first else { return }
        firstItem.title = registrationFailed
            ? AppStrings.Actions.showWindowUnavailable(hotkey: displayString)
            : AppStrings.Actions.showWindow(hotkey: displayString)
    }
    
    @objc private func showGhostwriter() {
        FloatingWindowManager.shared.show()
    }

    // MARK: - NSMenuDelegate

    /// Refreshes the launch-at-login checkmark each time the menu opens, so
    /// live prefs.toml edits are reflected without reopening the app.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let launchItem = menu.items.first { $0.action == #selector(toggleLaunchAtLogin) }
        launchItem?.state = AppSettings.shared.launchAtLogin ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        AppSettings.shared.launchAtLogin.toggle()
    }
    
    @objc private func openSettings() {
        PreferencesManager.shared.openPreferencesFile()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
