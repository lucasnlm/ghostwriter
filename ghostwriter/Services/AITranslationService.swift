//
//  AITranslationService.swift
//  ghostwriter
//

import Foundation
import os

final class AITranslationService: TranslationService {
    static let shared = AITranslationService()

    private let settings = AppSettings.shared

    func translate(
        text: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        tone: LanguageTone,
        context: String? = nil,
        promptMode: Bool = false,
        timeout: TimeInterval = 60
    ) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return ""
        }

        let (binaryPath, arguments, stdinPrompt) = try resolveCommand(
            for: settings.selectedProvider,
            text: trimmedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            tone: tone,
            context: context,
            promptMode: promptMode
        )

        return try await Self.executeCLIProcess(
            binaryPath: binaryPath,
            arguments: arguments,
            stdinPrompt: stdinPrompt,
            timeout: timeout
        )
    }

    // MARK: - Command Resolution

    private func resolveCommand(
        for provider: AIProvider,
        text: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        tone: LanguageTone,
        context: String?,
        promptMode: Bool
    ) throws -> (String, [String], String?) {
        let prompt = Self.buildPrompt(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            tone: tone,
            context: context,
            promptMode: promptMode
        )

        switch provider {
        case .agy, .claude, .opencode:
            let configuredPath = settings.configuredBinaryPath(for: provider)
            let name = provider.defaultBinaryName
            let binary = configuredPath.isEmpty ? (Self.findBinary(named: name) ?? name) : configuredPath
            guard Self.binaryExists(at: binary) else {
                throw TranslationError.cliNotFound(name)
            }
            return (binary, Self.substitutePrompt(in: provider.defaultArguments, prompt: prompt), nil)

        case .custom:
            let binary = settings.configuredBinaryPath(for: provider)
            guard !binary.isEmpty, Self.binaryExists(at: binary) else {
                throw TranslationError.cliNotFound(binary.isEmpty ? provider.displayName : binary)
            }
            let template = settings.customArguments
            let arguments = Self.parseArguments(template: template, prompt: prompt)
            // Without a {prompt} token there is nothing to substitute, so the
            // prompt is piped via stdin instead — keeping it off `argv` and
            // out of `ps` output, with no argument-length limits.
            let stdinPrompt = template.contains("{prompt}") ? nil : prompt
            return (binary, arguments, stdinPrompt)
        }
    }

    static func buildPrompt(
        text: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        tone: LanguageTone,
        context: String? = nil,
        promptMode: Bool = false
    ) -> String {
        let isSameLanguage = sourceLanguage == targetLanguage

        let taskDescription: String
        if promptMode {
            taskDescription = """
            You are an expert writing assistant.
            The user's input is an INSTRUCTION describing content to write, not text to translate
            (e.g., "A birthday message for a person called John Doe").

            Tasks:
            - Follow the instruction faithfully, honoring every name, fact, constraint, and requested format.
            - Write the result in \(targetLanguage.displayName).
            - Apply the conventions of \(targetLanguage.regionPromptInstruction).
            """
        } else if isSameLanguage {
            taskDescription = """
            You are an expert editor, proofreader, and writing assistant.
            The user has provided text in \(targetLanguage.displayName) to be improved, polished, and corrected.

            Tasks:
            - Fix all grammar, spelling, punctuation, typos, and syntax errors.
            - Enhance flow, clarity, and word choice while strictly maintaining the original meaning.
            - Apply the conventions of \(targetLanguage.regionPromptInstruction).
            """
        } else {
            let sourceInstruction = sourceLanguage == .auto
                ? "Source Language: Automatically detect the input language."
                : "Source Language: \(sourceLanguage.displayName) (\(sourceLanguage.regionPromptInstruction))."

            taskDescription = """
            You are an expert multilingual translator, editor, and writing assistant.

            Tasks:
            1. If the input text is in a different language than \(targetLanguage.displayName):
               - Translate it accurately and naturally into \(targetLanguage.displayName).
            2. If the input text is already in \(targetLanguage.displayName) (or if the input contains grammatical, spelling, or phrasing mistakes):
               - Fix all errors and rewrite/improve the text in polished \(targetLanguage.displayName).
            3. If adapting between regional dialects (e.g., pt-BR to pt-PT, or en-US to en-GB):
               - Convert spelling, vocabulary, pronouns, and phrasing to the target dialect.

            Language Specifications:
            - \(sourceInstruction)
            - Target Dialect & Region: \(targetLanguage.regionPromptInstruction)
            """
        }

        let contextBlock: String
        if let surrounding = context?.trimmingCharacters(in: .whitespacesAndNewlines), !surrounding.isEmpty {
            contextBlock = """

            Context — text immediately preceding the user's input in the same document or conversation.
            Use it ONLY to match tone, topic, terminology, and language. Do NOT translate it, repeat it,
            or continue it in the output:
            \(surrounding)
            """
        } else {
            contextBlock = ""
        }

        let outputOnlyRule = promptMode
            ? "- Output ONLY the requested content."
            : "- Output ONLY the final translated / improved text."
        let formattingRule = promptMode
            ? "- Format the result naturally, using paragraphs where appropriate."
            : "- Preserve original paragraphs, line breaks, punctuation style, and formatting structure."
        let inputLabel = promptMode ? "Instruction:" : "Text to process:"

        return """
        \(taskDescription)

        Tone & Style:
        - \(tone.displayName): \(tone.promptDescription)

        Strict output rules:
        \(outputOnlyRule)
        - Do NOT wrap in quotes.
        - Do NOT include greetings, preamble, explanations, notes, or commentary.
        - Do NOT wrap in markdown code blocks.
        \(formattingRule)
        \(contextBlock)

        \(inputLabel)
        \(text)
        """
    }

    /// Splits a whitespace-separated argument template and substitutes `{prompt}`.
    nonisolated static func parseArguments(template: String, prompt: String) -> [String] {
        let parts = template.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return substitutePrompt(in: parts, prompt: prompt)
    }

    /// Replaces the `{prompt}` token inside any argument.
    nonisolated static func substitutePrompt(in arguments: [String], prompt: String) -> [String] {
        arguments.map { argument in
            argument.contains("{prompt}")
                ? argument.replacingOccurrences(of: "{prompt}", with: prompt)
                : argument
        }
    }

    // MARK: - Binary Path Lookup

    nonisolated static func findBinary(named name: String) -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        let searchDirectories = [
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "\(home)/.gemini/antigravity-cli/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        for dir in searchDirectories {
            let candidate = "\(dir)/\(name)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Also check PATH
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.components(separatedBy: ":") {
                let candidate = "\(dir)/\(name)"
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    nonisolated static func binaryExists(at path: String) -> Bool {
        if path.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: path)
        }
        return findBinary(named: path) != nil
    }

    // MARK: - Process Execution

    /// Runs the CLI with stdout and stderr streamed concurrently (a child that
    /// fills one pipe while we block on the other would otherwise deadlock),
    /// terminating it on task cancellation or after `timeout` seconds.
    nonisolated private static func executeCLIProcess(
        binaryPath: String,
        arguments: [String],
        stdinPrompt: String?,
        timeout: TimeInterval
    ) async throws -> String {
        let process = Process()

        let resolvedPath = binaryPath.hasPrefix("/") ? binaryPath : (findBinary(named: binaryPath) ?? binaryPath)
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = arguments

        // Build rich PATH environment
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "\(home)/.gemini/antigravity-cli/bin",
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let stdinPrompt {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            do {
                try process.run()
            } catch {
                throw TranslationError.executionFailed("Failed to launch \(binaryPath): \(error.localizedDescription)")
            }
            // Feed the prompt from a background thread: a child that never
            // reads stdin must not block us on a full pipe buffer.
            let fd = stdinPipe.fileHandleForWriting.fileDescriptor
            let data = Data(stdinPrompt.utf8)
            DispatchQueue.global().async {
                writeAndClose(fd: fd, data: data)
            }
        } else {
            do {
                try process.run()
            } catch {
                throw TranslationError.executionFailed("Failed to launch \(binaryPath): \(error.localizedDescription)")
            }
        }

        let didTimeOut = OSAllocatedUnfairLock(initialState: false)
        let timeoutWork = DispatchWorkItem {
            guard process.isRunning else { return }
            didTimeOut.withLock { $0 = true }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        defer { timeoutWork.cancel() }

        let (outputData, errorData) = try await withTaskCancellationHandler {
            async let stdout = collectData(from: stdoutPipe.fileHandleForReading)
            async let stderr = collectData(from: stderrPipe.fileHandleForReading)
            return try await (stdout, stderr)
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        // Both pipes are at EOF by now, so this returns immediately.
        process.waitUntilExit()

        if didTimeOut.withLock({ $0 }) {
            throw TranslationError.timedOut
        }
        try Task.checkCancellation()

        let rawOutput = String(data: outputData, encoding: .utf8) ?? ""
        let rawError = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = rawError.isEmpty ? rawOutput : rawError
            throw TranslationError.executionFailed("Exited with code \(process.terminationStatus): \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let sanitized = sanitizeOutput(rawOutput)
        guard !sanitized.isEmpty else {
            throw TranslationError.emptyResponse
        }

        return sanitized
    }

    nonisolated private static func collectData(from handle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in handle.bytes {
            data.append(byte)
        }
        return data
    }

    /// POSIX write that silently gives up on EPIPE (child exited without
    /// reading stdin) instead of tripping the default SIGPIPE kill; SIGPIPE
    /// is ignored app-wide at launch.
    nonisolated private static func writeAndClose(fd: Int32, data: Data) {
        defer { close(fd) }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base + offset, raw.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    // MARK: - Output Sanitization

    nonisolated static func sanitizeOutput(_ output: String) -> String {
        // Strip ANSI escape sequences
        let stripped = output.replacingOccurrences(
            of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#,
            with: "",
            options: .regularExpression
        )

        var trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip code fence if the entire result was wrapped in ``` ... ```
        if trimmed.hasPrefix("```") && trimmed.hasSuffix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count >= 2 {
                let innerLines = lines.dropFirst().dropLast()
                trimmed = innerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }
}
