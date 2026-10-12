//
//  PreferencesManager.swift
//  ghostwriter
//

import Foundation
import AppKit

final class PreferencesManager {
    static let shared = PreferencesManager()

    static var configDirectoryURL: URL {
        // Test isolation: point at a temp directory instead of the user's
        // real config (see ghostwriterTests.setUp).
        if let override = ProcessInfo.processInfo.environment["GHOSTWRITER_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("ghostwriter", isDirectory: true)
    }

    static var fileURL: URL {
        configDirectoryURL.appendingPathComponent("prefs.toml", isDirectory: false)
    }

    private var fileWatcherSource: DispatchSourceFileSystemObject?

    init() {
        ensureFileExists()
        startWatching()
    }

    deinit {
        stopWatching()
    }

    // MARK: - File Management

    func ensureFileExists() {
        let dir = Self.configDirectoryURL
        let file = Self.fileURL

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: file.path) {
            let defaultContent = generateDefaultTOML()
            try? defaultContent.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func openPreferencesFile() {
        ensureFileExists()
        let url = Self.fileURL

        // Try opening with user default editor for .toml files
        if !NSWorkspace.shared.open(url) {
            // Fallback: open with TextEdit if no application is registered for .toml
            if let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: textEditURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        }
    }

    // MARK: - TOML Parsing & Updating

    func readPreferences() -> [String: String] {
        ensureFileExists()
        guard let content = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            return [:]
        }
        return parseTOML(content)
    }

    func parseTOML(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = Self.strippingInlineComment(from: line)
                .trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2 {
                let key = parts[0]
                var val = parts[1]
                if val.count >= 2,
                   (val.hasPrefix("\"") && val.hasSuffix("\"")) ||
                   (val.hasPrefix("'") && val.hasSuffix("'")) {
                    let inner = String(val.dropFirst().dropLast())
                    val = val.hasPrefix("\"") ? Self.unescapingTOMLString(inner) : inner
                }
                result[key] = val
            }
        }
        return result
    }

    /// Strips a trailing `#` comment, ignoring `#` characters inside quoted
    /// values and the escaped quotes within them.
    private static func strippingInlineComment(from line: String) -> String {
        var quote: Character? = nil
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if escaped {
                escaped = false
            } else if char == "\\", quote == "\"" {
                escaped = true
            } else if char == "#", quote == nil {
                return String(line[..<index])
            } else if char == "\"" || char == "'" {
                if quote == char {
                    quote = nil
                } else if quote == nil {
                    quote = char
                }
            }
            index = line.index(after: index)
        }
        return line
    }

    /// Reverses the `\\` and `\"` escapes written by `updateKey`.
    private static func unescapingTOMLString(_ string: String) -> String {
        var result = ""
        var escaped = false
        for char in string {
            if escaped {
                result.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                result.append(char)
            }
        }
        if escaped {
            result.append("\\")
        }
        return result
    }

    func updateKey(key: String, value: String, isString: Bool = true) {
        ensureFileExists()
        guard var content = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            return
        }

        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let formattedValue = isString ? "\"\(escapedValue)\"" : value
        var found = false
        var lines = content.components(separatedBy: .newlines)

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.first == key {
                lines[i] = "\(key) = \(formattedValue)"
                found = true
                break
            }
        }

        if !found {
            lines.append("\(key) = \(formattedValue)")
        }

        content = lines.joined(separator: "\n")
        try? content.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }

    private func generateDefaultTOML() -> String {
        return """
        # Ghostwriter Preferences
        # File: ~/.config/ghostwriter/prefs.toml
        # Edit this file to configure Ghostwriter. Changes take effect automatically.
        # Deleting a key restores its default value.

        # Global activation hotkey (e.g. "ctrl+cmd+g", "cmd+shift+space", "ctrl+opt+g")
        shortcut = "ctrl+cmd+g"

        # AI CLI Provider to use ("agy", "claude", "opencode", or "custom")
        provider = "agy"

        # Default source language (e.g. "pt-BR", "auto", "en-US", "es-ES", "fr-FR", etc.)
        source_language = "pt-BR"

        # Default target language (e.g. "en-US", "pt-BR", "pt-PT", "es-ES", etc.)
        target_language = "en-US"

        # Default tone: "formal", "informal", "concise", "friendly", "academic"
        tone = "formal"

        # Automatically paste translated/improved text into active app (true / false)
        auto_paste = true

        # Optional binary paths (uncomment if tools are installed in custom locations)
        # agy_path = "/usr/local/bin/agy"
        # claude_path = "/usr/local/bin/claude"
        # opencode_path = "/usr/local/bin/opencode"

        # Custom CLI tool configuration (used when provider = "custom")
        # If the arguments contain no {prompt} token, the prompt is piped via stdin instead.
        # custom_binary_path = "/opt/homebrew/bin/llm"
        # custom_arguments = "-m gpt-4o {prompt}"
        """
    }

    // MARK: - File Watcher

    func startWatching() {
        stopWatching()
        ensureFileExists()

        let fd = open(Self.fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                AppSettings.shared.reloadFromDisk()
                let flags = source.data
                if flags.contains(.rename) || flags.contains(.delete) {
                    // Re-bind watcher after atomic save by editors
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        MainActor.assumeIsolated {
                            self?.startWatching()
                        }
                    }
                }
            }
        }

        // The cancel handler must close the fd it was created with. Reading
        // self.fileDescriptor here would race with a concurrently re-bound
        // watcher and close the wrong (new) descriptor.
        source.setCancelHandler {
            close(fd)
        }

        fileWatcherSource = source
        source.resume()
    }

    func stopWatching() {
        if let source = fileWatcherSource {
            source.cancel()
            fileWatcherSource = nil
        }
    }
}
