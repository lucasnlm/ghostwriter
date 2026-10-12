//
//  ghostwriterTests.swift
//  ghostwriterTests
//

import XCTest
import SwiftUI
import AppKit
@testable import ghostwriter

final class ghostwriterTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Isolate preferences (TOML writes, file watching, hotkey settings
        // persistence) into a throwaway directory instead of the user's
        // real ~/.config/ghostwriter/prefs.toml. Must run before any
        // PreferencesManager/AppSettings singleton is first touched.
        setenv("GHOSTWRITER_CONFIG_DIR",
               NSTemporaryDirectory() + "/ghostwriter-tests-" + UUID().uuidString,
               1)
    }

    func testLanguageRegionsAndDisplayNames() throws {
        XCTAssertFalse(Language.pt_BR.displayName.isEmpty)
        XCTAssertFalse(Language.pt_PT.displayName.isEmpty)
        XCTAssertFalse(Language.en_US.displayName.isEmpty)
        XCTAssertFalse(Language.en_GB.displayName.isEmpty)

        XCTAssertFalse(Language.pt_BR.regionPromptInstruction.isEmpty)
        XCTAssertFalse(Language.pt_PT.regionPromptInstruction.isEmpty)

        // Auto-detect is for source only
        XCTAssertTrue(Language.sourceLanguages.contains(.auto))
        XCTAssertFalse(Language.targetLanguages.contains(.auto))
    }

    func testLanguageTones() throws {
        for tone in LanguageTone.allCases {
            XCTAssertFalse(tone.displayName.isEmpty)
            XCTAssertFalse(tone.promptDescription.isEmpty)
        }
    }

    func testCLIProviders() throws {
        XCTAssertEqual(AIProvider.agy.defaultBinaryName, "agy")
        XCTAssertEqual(AIProvider.claude.defaultBinaryName, "claude")
        XCTAssertEqual(AIProvider.opencode.defaultBinaryName, "opencode")

        XCTAssertEqual(AIProvider.agy.defaultArguments, ["-p", "{prompt}"])
        XCTAssertEqual(AIProvider.claude.defaultArguments, ["-p", "{prompt}"])
        XCTAssertEqual(AIProvider.opencode.defaultArguments, ["run", "{prompt}"])
    }

    func testAppSettingsPersistence() throws {
        let settings = AppSettings.shared
        let originalSource = settings.sourceLanguage
        let originalTarget = settings.targetLanguage
        let originalTone = settings.selectedTone
        let originalProvider = settings.selectedProvider
        defer {
            settings.sourceLanguage = originalSource
            settings.targetLanguage = originalTarget
            settings.selectedTone = originalTone
            settings.selectedProvider = originalProvider
        }

        settings.sourceLanguage = .pt_BR
        settings.targetLanguage = .en_US
        settings.selectedTone = .formal
        settings.selectedProvider = .agy

        XCTAssertEqual(settings.sourceLanguage, .pt_BR)
        XCTAssertEqual(settings.targetLanguage, .en_US)
        XCTAssertEqual(settings.selectedTone, .formal)
        XCTAssertEqual(settings.selectedProvider, .agy)

        // Verify UserDefaults sync
        XCTAssertEqual(UserDefaults.standard.string(forKey: "sourceLanguage"), "pt-BR")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "targetLanguage"), "en-US")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectedProvider"), "agy")
    }

    func testReloadFromDiskRevertsDeletedKeysToDefaults() throws {
        let settings = AppSettings.shared
        let originalTarget = settings.targetLanguage
        defer { settings.targetLanguage = originalTarget }

        // Override via TOML, then delete the key: the override must disappear.
        PreferencesManager.shared.updateKey(key: "target_language", value: "fr-FR")
        settings.reloadFromDisk()
        XCTAssertEqual(settings.targetLanguage, .fr_FR)

        let fileURL = PreferencesManager.fileURL
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let withoutKey = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("target_language") }
        try withoutKey.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        settings.reloadFromDisk()
        XCTAssertEqual(settings.targetLanguage, .en_US, "An absent TOML key must revert to its default, not keep the stale UserDefaults value")
    }

    func testTextImprovementPromptWhenSameLanguage() throws {
        let prompt = AITranslationService.buildPrompt(
            text: "nois vai na praia amanha",
            sourceLanguage: .pt_BR,
            targetLanguage: .pt_BR,
            tone: .formal
        )

        XCTAssertTrue(prompt.contains("editor, proofreader, and writing assistant"))
        XCTAssertTrue(prompt.contains("Fix all grammar, spelling"))
        XCTAssertTrue(prompt.contains("nois vai na praia amanha"))
    }

    func testTranslationAndImprovementPromptWhenDifferentLanguage() throws {
        let prompt = AITranslationService.buildPrompt(
            text: "eu preciso de ajuda com isso",
            sourceLanguage: .pt_BR,
            targetLanguage: .pt_PT,
            tone: .informal
        )

        XCTAssertTrue(prompt.contains("eu preciso de ajuda com isso"))
    }

    func testBuildPromptIncludesSurroundingContextWhenProvided() throws {
        let prompt = AITranslationService.buildPrompt(
            text: "valeu, fica pra próxima",
            sourceLanguage: .pt_BR,
            targetLanguage: .en_US,
            tone: .informal,
            context: "  Remarcamos a reunião para sexta.  "
        )

        XCTAssertTrue(prompt.contains("valeu, fica pra próxima"))
        XCTAssertTrue(prompt.contains("Remarcamos a reunião para sexta."))
        XCTAssertTrue(prompt.contains("Do NOT translate it, repeat it"))
    }

    func testBuildPromptOmitsContextSectionWhenAbsent() throws {
        let prompt = AITranslationService.buildPrompt(
            text: "oi",
            sourceLanguage: .pt_BR,
            targetLanguage: .en_US,
            tone: .formal
        )

        XCTAssertFalse(prompt.contains("Context —"))
    }

    func testBuildPromptInPromptModeTreatsInputAsInstruction() throws {
        let prompt = AITranslationService.buildPrompt(
            text: "A birthday message for a person called John Doe",
            sourceLanguage: .pt_BR,
            targetLanguage: .pt_PT,
            tone: .friendly,
            promptMode: true
        )

        XCTAssertTrue(prompt.contains("A birthday message for a person called John Doe"))
        XCTAssertTrue(prompt.contains("INSTRUCTION"))
        XCTAssertTrue(prompt.contains("European Portuguese (pt-PT)"))
        XCTAssertTrue(prompt.contains("Output ONLY the requested content."))
        // Must not describe a translation task
        XCTAssertFalse(prompt.contains("multilingual translator"))
        XCTAssertFalse(prompt.contains("Text to process:"))
    }

    func testSubstitutePromptToken() throws {
        XCTAssertEqual(
            AITranslationService.substitutePrompt(in: ["-p", "{prompt}"], prompt: "hi there"),
            ["-p", "hi there"]
        )
        XCTAssertEqual(
            AITranslationService.parseArguments(template: "-m gpt-4o {prompt}", prompt: "x"),
            ["-m", "gpt-4o", "x"]
        )
        XCTAssertEqual(
            AITranslationService.substitutePrompt(in: ["run"], prompt: "x"),
            ["run"]
        )
    }

    func testCaretPlacementCalculation() throws {
        let contentSize = NSSize(width: 390, height: 185)
        let placement = CaretLocator.calculatePlacement(contentSize: contentSize, shadowPadding: 8)

        XCTAssertGreaterThan(placement.arrowX, 0)
        XCTAssertLessThanOrEqual(placement.arrowX, contentSize.width)

        // Also test backwards compatible overload
        let legacyPlacement = CaretLocator.calculatePlacement(forWindowSize: contentSize)
        XCTAssertGreaterThan(legacyPlacement.arrowX, 0)
        XCTAssertLessThanOrEqual(legacyPlacement.arrowX, contentSize.width)
    }

    func testIsValidCaretRect() throws {
        // Zero-width insertion point (blinking text cursor)
        let insertionPoint = CGRect(x: 100, y: 200, width: 0, height: 18)
        XCTAssertTrue(CaretLocator.isValidCaretRect(insertionPoint))

        // Non-zero width text selection
        let textSelection = CGRect(x: 100, y: 200, width: 85, height: 18)
        XCTAssertTrue(CaretLocator.isValidCaretRect(textSelection))

        // Invalid rects
        XCTAssertFalse(CaretLocator.isValidCaretRect(CGRect.null))
        XCTAssertFalse(CaretLocator.isValidCaretRect(CGRect.infinite))
        XCTAssertFalse(CaretLocator.isValidCaretRect(CGRect(x: 0, y: 0, width: 100, height: 0)))
        XCTAssertFalse(CaretLocator.isValidCaretRect(CGRect(x: 0, y: 0, width: 100, height: -10)))
        XCTAssertFalse(CaretLocator.isValidCaretRect(CGRect(x: 0, y: 0, width: -5, height: 18)))
    }

    func testCarbonToAppKitConversion() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No attached screen to compare against")
        }
        let screenHeight = screen.frame.height

        // Carbon top-left coordinate: origin at (100, 50) with size (200, 20)
        let carbonRect = CGRect(x: 100, y: 50, width: 200, height: 20)
        let appKitRect = CaretLocator.convertCarbonToAppKit(carbonRect)

        XCTAssertEqual(appKitRect.origin.x, 100)
        XCTAssertEqual(appKitRect.origin.y, screenHeight - 50 - 20)
        XCTAssertEqual(appKitRect.width, 200)
        XCTAssertEqual(appKitRect.height, 20)
    }

    func testCaretPlacementFlipsAboveWhenNearBottom() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No attached screen to place a caret on")
        }
        let visibleFrame = screen.visibleFrame
        let contentSize = NSSize(width: 390, height: 185)

        // Caret positioned very near the bottom of the screen (AppKit Y near visibleFrame.minY)
        let lowCaret = NSRect(x: visibleFrame.midX, y: visibleFrame.minY + 20, width: 1, height: 18)
        let placement = CaretLocator.calculatePlacement(for: lowCaret, contentSize: contentSize, shadowPadding: 8)

        // Because bubbleHeight (185) > 20, it would bleed off the bottom, so it must flip above the caret
        XCTAssertFalse(placement.arrowOnTop, "When near the bottom of the screen, bubble must flip above the caret with arrow at the bottom")
        XCTAssertGreaterThanOrEqual(placement.windowOrigin.y + 8, lowCaret.maxY)
    }

    func testCaretPlacementClampsHorizontallyNearScreenEdges() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No attached screen to place a caret on")
        }
        let visibleFrame = screen.visibleFrame
        let contentSize = NSSize(width: 390, height: 185)

        // Caret at extreme left edge
        let leftCaret = NSRect(x: visibleFrame.minX + 2, y: visibleFrame.midY, width: 1, height: 18)
        let leftPlacement = CaretLocator.calculatePlacement(for: leftCaret, contentSize: contentSize, shadowPadding: 8)
        XCTAssertGreaterThanOrEqual(leftPlacement.windowOrigin.x + 8, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(leftPlacement.arrowX, 24)

        // Caret at extreme right edge
        let rightCaret = NSRect(x: visibleFrame.maxX - 2, y: visibleFrame.midY, width: 1, height: 18)
        let rightPlacement = CaretLocator.calculatePlacement(for: rightCaret, contentSize: contentSize, shadowPadding: 8)
        XCTAssertLessThanOrEqual(rightPlacement.windowOrigin.x + 8 + contentSize.width, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(rightPlacement.arrowX, contentSize.width - 24)
    }

    @MainActor
    func testFloatingPopupViewRenderingHasNoTopArtifact() throws {
        let view = FloatingPopupView()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: FloatingWindowManager.windowSize)

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not create bitmapImageRepForCachingDisplay")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        // In the top outer shadow margin (away from the center arrow), alpha should be transparent (< 0.05)
        var maxAlphaInTopCorners: CGFloat = 0.0
        for y in 0..<4 {
            for x in [10, 20, 30, 40, Int(FloatingWindowManager.windowSize.width) - 40, Int(FloatingWindowManager.windowSize.width) - 10] {
                if let color = rep.colorAt(x: x, y: y) {
                    maxAlphaInTopCorners = max(maxAlphaInTopCorners, color.alphaComponent)
                }
            }
        }

        XCTAssertLessThan(maxAlphaInTopCorners, 0.05, "Top corners of the window must remain transparent with no horizontal bar or border artifact")
    }

    func testSanitizeOutput() throws {
        // Test ANSI stripping
        let ansiString = "\u{001B}[32mHello world\u{001B}[0m"
        XCTAssertEqual(AITranslationService.sanitizeOutput(ansiString), "Hello world")

        // Test code fence stripping
        let markdownFenced = "```\nTranslated text\n```"
        XCTAssertEqual(AITranslationService.sanitizeOutput(markdownFenced), "Translated text")

        // Test whitespace trimming
        let whitespaceString = "   \n  Olá mundo  \n\n  "
        XCTAssertEqual(AITranslationService.sanitizeOutput(whitespaceString), "Olá mundo")
    }

    func testMissingCLIToolThrowsError() async {
        let settings = AppSettings.shared
        let originalProvider = settings.selectedProvider
        let originalCustomPath = settings.customBinaryPath
        defer {
            settings.selectedProvider = originalProvider
            settings.customBinaryPath = originalCustomPath
        }

        settings.selectedProvider = .custom
        settings.customBinaryPath = "/non/existent/binary/path/xyz"

        do {
            _ = try await AITranslationService.shared.translate(
                text: "Olá mundo",
                sourceLanguage: .pt_BR,
                targetLanguage: .en_US,
                tone: .formal
            )
            XCTFail("Should have thrown cliNotFound error")
        } catch let error as TranslationError {
            switch error {
            case .cliNotFound(let name):
                XCTAssertTrue(name.contains("xyz"))
            default:
                XCTFail("Unexpected TranslationError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomCLITimesOutAndTerminatesHungProcess() async {
        let settings = AppSettings.shared
        let originalProvider = settings.selectedProvider
        let originalPath = settings.customBinaryPath
        let originalArgs = settings.customArguments
        defer {
            settings.selectedProvider = originalProvider
            settings.customBinaryPath = originalPath
            settings.customArguments = originalArgs
        }

        settings.selectedProvider = .custom
        settings.customBinaryPath = "/bin/sleep"
        // No {prompt} token: the prompt is piped via stdin, which sleep ignores.
        settings.customArguments = "5"

        do {
            _ = try await AITranslationService.shared.translate(
                text: "olá",
                sourceLanguage: .pt_BR,
                targetLanguage: .en_US,
                tone: .formal,
                timeout: 0.5
            )
            XCTFail("Expected a timeout error")
        } catch let error as TranslationError {
            guard case .timedOut = error else {
                return XCTFail("Unexpected TranslationError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreferencesManagerTOMLParsingAndUpdating() throws {
        let manager = PreferencesManager.shared
        manager.ensureFileExists()

        let sampleTOML = """
        # Comments should be ignored
        provider = "claude"
        source_language = "pt-PT"
        target_language = "es-ES"
        tone = "concise"
        auto_paste = false
        """

        let parsed = manager.parseTOML(sampleTOML)
        XCTAssertEqual(parsed["provider"], "claude")
        XCTAssertEqual(parsed["source_language"], "pt-PT")
        XCTAssertEqual(parsed["target_language"], "es-ES")
        XCTAssertEqual(parsed["tone"], "concise")
        XCTAssertEqual(parsed["auto_paste"], "false")
    }

    func testPreferencesManagerTOMLParsingStripsInlineComments() throws {
        let manager = PreferencesManager.shared

        let inlineCommentTOML = """
        shortcut = "ctrl+cmd+g"  # Global hotkey
        provider = "agy" # CLI provider
        auto_paste = false # disabled
        quoted_hash = "value # not a comment"
        escaped_quote = "say \\"hi\\" # also not a comment"
        """

        let parsed = manager.parseTOML(inlineCommentTOML)
        XCTAssertEqual(parsed["shortcut"], "ctrl+cmd+g")
        XCTAssertEqual(parsed["provider"], "agy")
        XCTAssertEqual(parsed["auto_paste"], "false")
        XCTAssertEqual(parsed["quoted_hash"], "value # not a comment")
        XCTAssertEqual(parsed["escaped_quote"], "say \"hi\" # also not a comment")
    }

    func testTOMLValuesWithQuotesAndBackslashesRoundTrip() throws {
        let manager = PreferencesManager.shared

        let tricky = "/opt/bin/my \"tool\" \\ path"
        manager.updateKey(key: "custom_binary_path", value: tricky)

        XCTAssertEqual(
            manager.readPreferences()["custom_binary_path"],
            tricky,
            "Values containing quotes and backslashes must survive a TOML write/read round trip"
        )
    }

    func testPreferencesFileExistsAndIsCreated() throws {
        let manager = PreferencesManager.shared
        manager.ensureFileExists()

        XCTAssertTrue(FileManager.default.fileExists(atPath: PreferencesManager.fileURL.path))
        let content = try String(contentsOf: PreferencesManager.fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("shortcut"))
        XCTAssertTrue(content.contains("provider"))
        XCTAssertTrue(content.contains("source_language"))
        XCTAssertTrue(content.contains("target_language"))
    }

    func testHotKeyShortcutParsing() throws {
        // Standard ctrl+cmd+g
        let parsedStandard = HotKeyManager.parseShortcut("ctrl+cmd+g")
        XCTAssertNotNil(parsedStandard)
        XCTAssertEqual(parsedStandard?.displayString, "⌃⌘G")

        // cmd+shift+space
        let parsedSpace = HotKeyManager.parseShortcut("cmd+shift+space")
        XCTAssertNotNil(parsedSpace)
        XCTAssertEqual(parsedSpace?.displayString, "⇧⌘Space")

        // control+option+a
        let parsedOpt = HotKeyManager.parseShortcut("control+option+a")
        XCTAssertNotNil(parsedOpt)
        XCTAssertEqual(parsedOpt?.displayString, "⌃⌥A")

        // Invalid returns nil
        let parsedInvalid = HotKeyManager.parseShortcut("")
        XCTAssertNil(parsedInvalid)
    }

    func testParseShortcutRejectsUnknownTokensAndDuplicateKeys() throws {
        // Unknown tokens must not be silently ignored
        XCTAssertNil(HotKeyManager.parseShortcut("ctrl+cmd+banana+g"))
        // Nor multiple key tokens
        XCTAssertNil(HotKeyManager.parseShortcut("ctrl+cmd+g+j"))
        // Sanity: the well-formed variant still parses
        XCTAssertNotNil(HotKeyManager.parseShortcut("ctrl+cmd+g"))
    }

    func testAppSettingsShortcutUpdating() throws {
        let settings = AppSettings.shared
        let originalShortcut = settings.shortcut
        defer { settings.shortcut = originalShortcut }

        settings.shortcut = "cmd+shift+space"
        XCTAssertEqual(HotKeyManager.shared.currentShortcut, "cmd+shift+space")
        XCTAssertEqual(HotKeyManager.shared.displayString, "⇧⌘Space")
    }
}
