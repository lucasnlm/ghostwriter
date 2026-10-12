//
//  HotKeyManager.swift
//  ghostwriter
//

import Carbon
import AppKit

struct ParsedHotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayString: String
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onHotKeyPressed: (() -> Void)?

    private(set) var currentShortcut: String = "ctrl+cmd+g"
    private(set) var displayString: String = "⌃⌘G"
    private(set) var isRegistrationFailed = false

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func register(shortcut: String? = nil) {
        let sc = shortcut ?? currentShortcut
        updateShortcut(sc)
    }

    func updateShortcut(_ shortcutString: String) {
        let parsedInput = Self.parseShortcut(shortcutString)
        guard let parsed = parsedInput ?? Self.parseShortcut("ctrl+cmd+g") else {
            return
        }

        // Only record the requested string when it actually parsed; otherwise
        // keep the fallback so an invalid value is not persisted and re-fed
        // into parsing on the next launch.
        currentShortcut = parsedInput != nil ? shortcutString : "ctrl+cmd+g"
        displayString = parsed.displayString

        installEventHandlerIfNeeded()
        unregisterHotKey()

        isRegistrationFailed = false
        if Self.isRunningTests {
            // Registering real system-wide hotkeys from the test runner leaks
            // global state onto the host machine; parsing state still updates.
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x47485354), id: 1) // 'GHST'
        let regStatus = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            isRegistrationFailed = true
            print("Failed to register global hotkey '\(shortcutString)': \(regStatus)")
        }

        // Surface registration problems (e.g. a shortcut conflict with another
        // utility) in the menu bar instead of failing silently.
        MenuBarManager.shared.updateShortcutTitle(
            parsed.displayString,
            registrationFailed: isRegistrationFailed
        )
    }

    /// Installs the shared Carbon event handler once; shortcut changes only
    /// re-register the hot key itself.
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    // Carbon delivers on the main run loop; make the actor
                    // isolation explicit for the compiler across the C callback.
                    MainActor.assumeIsolated {
                        manager.onHotKeyPressed?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            print("Failed to install Carbon event handler: \(status)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func unregister() {
        unregisterHotKey()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Shortcut Parsing

    static func parseShortcut(_ string: String) -> ParsedHotKey? {
        let raw = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }

        let separators = CharacterSet(charactersIn: "+- ")
        let tokens = raw.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        var keyName = ""

        for token in tokens {
            switch token {
            case "ctrl", "control", "ctl", "⌃":
                modifiers |= UInt32(controlKey)
            case "cmd", "command", "⌘":
                modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt", "⌥":
                modifiers |= UInt32(optionKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            default:
                // Reject unknown tokens and multiple key tokens instead of
                // silently registering something different than requested.
                guard let parsed = parseKeyToken(token), keyCode == nil else { return nil }
                keyCode = parsed.0
                keyName = parsed.1
            }
        }

        guard let code = keyCode else { return nil }

        // If no modifiers specified, default to cmd+ctrl
        if modifiers == 0 {
            modifiers = UInt32(cmdKey | controlKey)
        }

        var modSymbols = ""
        if (modifiers & UInt32(controlKey)) != 0 { modSymbols += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { modSymbols += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { modSymbols += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { modSymbols += "⌘" }

        let display = "\(modSymbols)\(keyName)"
        return ParsedHotKey(keyCode: code, modifiers: modifiers, displayString: display)
    }

    private static func parseKeyToken(_ token: String) -> (UInt32, String)? {
        switch token {
        case "a": return (UInt32(kVK_ANSI_A), "A")
        case "b": return (UInt32(kVK_ANSI_B), "B")
        case "c": return (UInt32(kVK_ANSI_C), "C")
        case "d": return (UInt32(kVK_ANSI_D), "D")
        case "e": return (UInt32(kVK_ANSI_E), "E")
        case "f": return (UInt32(kVK_ANSI_F), "F")
        case "g": return (UInt32(kVK_ANSI_G), "G")
        case "h": return (UInt32(kVK_ANSI_H), "H")
        case "i": return (UInt32(kVK_ANSI_I), "I")
        case "j": return (UInt32(kVK_ANSI_J), "J")
        case "k": return (UInt32(kVK_ANSI_K), "K")
        case "l": return (UInt32(kVK_ANSI_L), "L")
        case "m": return (UInt32(kVK_ANSI_M), "M")
        case "n": return (UInt32(kVK_ANSI_N), "N")
        case "o": return (UInt32(kVK_ANSI_O), "O")
        case "p": return (UInt32(kVK_ANSI_P), "P")
        case "q": return (UInt32(kVK_ANSI_Q), "Q")
        case "r": return (UInt32(kVK_ANSI_R), "R")
        case "s": return (UInt32(kVK_ANSI_S), "S")
        case "t": return (UInt32(kVK_ANSI_T), "T")
        case "u": return (UInt32(kVK_ANSI_U), "U")
        case "v": return (UInt32(kVK_ANSI_V), "V")
        case "w": return (UInt32(kVK_ANSI_W), "W")
        case "x": return (UInt32(kVK_ANSI_X), "X")
        case "y": return (UInt32(kVK_ANSI_Y), "Y")
        case "z": return (UInt32(kVK_ANSI_Z), "Z")
        case "0": return (UInt32(kVK_ANSI_0), "0")
        case "1": return (UInt32(kVK_ANSI_1), "1")
        case "2": return (UInt32(kVK_ANSI_2), "2")
        case "3": return (UInt32(kVK_ANSI_3), "3")
        case "4": return (UInt32(kVK_ANSI_4), "4")
        case "5": return (UInt32(kVK_ANSI_5), "5")
        case "6": return (UInt32(kVK_ANSI_6), "6")
        case "7": return (UInt32(kVK_ANSI_7), "7")
        case "8": return (UInt32(kVK_ANSI_8), "8")
        case "9": return (UInt32(kVK_ANSI_9), "9")
        case "space": return (UInt32(kVK_Space), "Space")
        case "return", "enter": return (UInt32(kVK_Return), "↩")
        case "tab": return (UInt32(kVK_Tab), "⇥")
        case "esc", "escape": return (UInt32(kVK_Escape), "Esc")
        case "f1": return (UInt32(kVK_F1), "F1")
        case "f2": return (UInt32(kVK_F2), "F2")
        case "f3": return (UInt32(kVK_F3), "F3")
        case "f4": return (UInt32(kVK_F4), "F4")
        case "f5": return (UInt32(kVK_F5), "F5")
        case "f6": return (UInt32(kVK_F6), "F6")
        case "f7": return (UInt32(kVK_F7), "F7")
        case "f8": return (UInt32(kVK_F8), "F8")
        case "f9": return (UInt32(kVK_F9), "F9")
        case "f10": return (UInt32(kVK_F10), "F10")
        case "f11": return (UInt32(kVK_F11), "F11")
        case "f12": return (UInt32(kVK_F12), "F12")
        default: return nil
        }
    }

    deinit {
        unregister()
    }
}
