//
//  TextInserter.swift
//  ghostwriter
//

import AppKit
import ApplicationServices

/// Snapshot of the pasteboard contents so the user's clipboard can be
/// restored after the synthetic paste.
private struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init?(pasteboard: NSPasteboard) {
        guard let current = pasteboard.pasteboardItems, !current.isEmpty else { return nil }
        var collected: [[NSPasteboard.PasteboardType: Data]] = []
        for item in current {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            if !entry.isEmpty {
                collected.append(entry)
            }
        }
        guard !collected.isEmpty else { return nil }
        self.items = collected
    }

    func restore(to pasteboard: NSPasteboard) {
        let restored = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(restored)
    }
}

final class TextInserter {
    static let shared = TextInserter()

    private let appTracker = ActiveAppTracker.shared

    /// Prompts for accessibility permission once, on first launch without it —
    /// it is needed both for caret placement and for the synthetic ⌘V.
    static func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didRequestAccessibilityPermission") else { return }
        defaults.set(true, forKey: "didRequestAccessibilityPermission")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Inserts the translated text into the previously active application.
    /// When `auto_paste` is disabled, the text is only placed on the clipboard
    /// and the previous application is reactivated, without a synthetic ⌘V.
    /// When pasting, the user's prior clipboard contents are restored afterwards.
    func insertText(_ text: String) async {
        guard !text.isEmpty else { return }

        // 1. Put text into system pasteboard, remembering what the user had there
        let pasteboard = NSPasteboard.general
        let saved = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCountAfterWrite = pasteboard.changeCount

        // 2. Reactivate the previous application
        appTracker.reactivatePreviousApp()

        // 3. Honor the auto_paste preference before simulating keystrokes
        guard AppSettings.shared.autoPaste else { return }

        // 4. Wait until the target app actually has focus; on failure the result
        //    stays on the clipboard so the user can paste it manually.
        guard await waitForTargetAppFocus() else { return }

        // 5. Synthesize Command + V keystroke
        synthesizePasteCommand()

        // 6. Give the target app time to read the pasteboard, then put back what
        //    the user had copied — unless something else wrote to it meanwhile.
        if let saved {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if pasteboard.changeCount == changeCountAfterWrite {
                saved.restore(to: pasteboard)
            }
        }
    }

    /// Waits until the previous application is frontmost (bounded), so the
    /// synthetic ⌘V can never be sent to the wrong app.
    private func waitForTargetAppFocus(timeout: TimeInterval = 1.0) async -> Bool {
        guard let target = appTracker.previousApp, !target.isTerminated else {
            try? await Task.sleep(nanoseconds: 120_000_000)
            return true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isFrontmost(target) {
                try? await Task.sleep(nanoseconds: 50_000_000) // let focus settle
                return true
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return isFrontmost(target)
    }

    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func synthesizePasteCommand() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual key code for 'V'

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
