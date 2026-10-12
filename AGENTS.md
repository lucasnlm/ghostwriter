# Ghostwriter - Developer & Agent Guide

## Overview

**Ghostwriter** is a lightweight, native macOS quick-translation and writing assistant utility. Inspired by the native macOS Character/Emoji picker (`Control + Command + Space`), Ghostwriter opens a minimalist conversation bubble attached directly to the active text caret whenever the user presses **`Control + Command + G`**.

It allows users to write in any language (or imperfect syntax) and instantly either:
1. **Translate** to a chosen target language/dialect (e.g., `pt-BR → en-US`), or
2. **Improve & Proofread** text within the same language/dialect (e.g., `pt-BR → pt-BR`), fixing grammar, spelling, punctuation, and adapting tone.

Once completed (via `Command + Return` / `⌘⏎`), Ghostwriter automatically inserts the result directly into whatever application the user was typing in (Slack, Notes, Messages, Chrome, Xcode, etc.).

---

## Architecture & Core Subsystems

```
┌─────────────────────────────────────────────────────────────┐
│                       Target Application                    │
│   (User typing in Slack, Notes, Safari, TextEdit, etc.)     │
└──────────────▲───────────────────────────────┬──────────────┘
               │                               │
       Paste via CGEvent               Press ⌃⌘G
       (TextInserter)                          │
               │                               ▼
┌──────────────┴──────────────┐   ┌───────────────────────────┐
│     FloatingWindowManager   │   │       HotKeyManager       │
│  (CaretLocator + NSPanel)   │◄──┤   (Carbon RegisterHotKey) │
└──────────────┬──────────────┘   └───────────────────────────┘
               │
         Displays View
               │
               ▼
┌──────────────────────────────┐
│      FloatingPopupView       │
│  (SpeechBubbleShape + Menu)  │
└──────────────┬──────────────┘
               │
          User presses ⌘⏎
               │
               ▼
┌──────────────────────────────┐
│    AITranslationService      │
│  (CLI: agy, claude, opencode)│
└──────────────────────────────┘
```

### 1. Global Hotkey (`HotKeyManager.swift`)
- Uses Carbon's `RegisterEventHotKey` API (`Carbon.HIToolbox`) with dynamic shortcut parsing (e.g. `ctrl+cmd+g`, `cmd+shift+space`, etc.) loaded from `prefs.toml`.
- Dynamically updates registered hotkey and menu bar status item when `shortcut` changes in `prefs.toml`.
- **Advantage**: Does NOT require input monitoring or special permissions just to register and listen for the hotkey.

### 2. Caret Detection & Positioning (`CaretLocator.swift`)
- When triggered, Ghostwriter queries the macOS Accessibility API (`AXUIElement`):
  - Resolves target app via `NSWorkspace.shared.frontmostApplication` or `ActiveAppTracker.shared.previousApp`.
  - Queries system-wide focus (`AXUIElementCreateSystemWide()`) and falls back to target application focus (`AXUIElementCreateApplication()`).
  - Drills down through container hierarchies (`AXWindow`, `AXSplitGroup`, `AXScrollArea`, `AXGroup`) up to 4 levels to reach the focused leaf text element.
  - Retrieves the text range (`kAXSelectedTextRangeAttribute`) and queries its bounding rect (`kAXBoundsForRangeParameterizedAttribute`).
  - **Insertion Point Handling**: Caret insertion points have `width == 0` and `height > 0`. Ghostwriter validates `size.height > 0 && size.width >= 0` rather than calling `CGRect.isEmpty` (which erroneously returns `true` when width is zero).
  - **Engine Fallbacks**: If zero-length range queries fail (common in some Chromium/WebKit engines), queries leading edge of forward character `(loc, 1)` or trailing edge of backward character `(loc - 1, 1)`.
  - **Compact Field Fallback**: If range bounds are unavailable on single-line inputs (height ≤ 60pt), estimates caret at the element's left padding.
- **Typing Context & Caret Snapshot** (`captureSnapshot()`): a *single* AX pass per popup show captures both the caret rect and the typing context. It reads `kAXSelectedTextAttribute` (current selection → pre-fills the popup input) and `kAXValueAttribute` + `kAXSelectedTextRangeAttribute` (text preceding the selection/caret, capped at ~2000 chars → passed to `AITranslationService.buildPrompt` as tone/topic context that is never translated or echoed back).
- **AX Messaging Timeouts**: `AXUIElementSetMessagingTimeout` (0.5s) is applied to every queried element so a busy or hung target app cannot freeze the popup on ⌃⌘G.
- Converts coordinates from Carbon/Accessibility top-left screen coordinates to AppKit bottom-left screen coordinates.
- **Placement Logic**:
  - Automatically positions the popup window directly beneath the caret with the speech bubble arrow pointing up.
  - If near the bottom edge of the screen, flips above the caret with the arrow pointing down.
  - Falls back to the current mouse cursor location or screen center if accessibility caret bounds are unavailable.

### 3. Window & Conversation Bubble (`FloatingWindowManager.swift` & `SpeechBubbleShape.swift`)
- Uses a borderless, non-activating `NSPanel` (`styleMask: [.borderless, .nonactivatingPanel]`, `level: .floating`).
- `panel.hasShadow = false`: AppKit's rectangular window shadow and window frame rim are strictly disabled to prevent WindowServer from drawing a rectangular border/line across the top edge behind the speech bubble arrow.
- Window size incorporates transparent outer `shadowPadding` (8pt) around the `contentSize` (390×185pt), allowing SwiftUI's `.shadow()` on `SpeechBubbleShape` to feather smoothly on all sides without edge clipping.
- Drawn using `SpeechBubbleShape`, a custom SwiftUI shape providing a dynamic arrow aligned with the caret's X-coordinate.
- Backed by native `.ultraThinMaterial` liquid glass with popover shadows and subtle white edge stroke, layered with a theme-adaptive tint (brighter white in light mode, deeper charcoal in dark mode).
- Auto-dismisses on `Escape` key (`cancelOperation`), upon successful text insertion, or when the user clicks anywhere outside the panel (global + local `NSEvent` mouse-down monitors, installed on show and removed on hide).

### 4. Text Insertion Engine (`TextInserter.swift` & `ActiveAppTracker.swift`)
- Tracks the paste target from launch (`ActiveAppTracker.shared.start()` observes `NSWorkspace.didActivateApplicationNotification`), so even the first menu-bar invocation has a valid previous app.
- On submission:
  1. Snapshots the user's current clipboard, then copies the translated/improved text to `NSPasteboard.general`.
  2. Dismisses the Ghostwriter window.
  3. Reactivates the target application (`app.activate()`).
  4. Waits (bounded, ~1s polling) until the target app is actually frontmost; the synthetic paste is skipped if focus never lands, leaving the result on the clipboard.
  5. Synthesizes a `Command + V` keystroke using `CGEvent` to paste directly at the cursor.
  6. Restores the user's prior clipboard contents ~350ms after the paste (unless something else wrote to the pasteboard meanwhile).

### 5. CLI-Based AI Provider (`AITranslationService.swift`)
- **No external HTTP API keys required** by default. Executes user's local AI command-line tools via `Process`:
  - **`agy`**: `agy -p "<prompt>"`
  - **`claude`**: `claude -p "<prompt>"`
  - **`opencode`**: `opencode run "<prompt>"`
  - **Custom CLI**: Customizable binary path and argument template with `{prompt}` token. If the template contains no `{prompt}` token, the prompt is piped to the child via **stdin** (keeps it off `argv`/`ps`; requires SIGPIPE to stay ignored, which `AppDelegate` does at launch).
- **Timeout & Cancellation**: the child is terminated (SIGTERM) on task cancellation (Escape/dismiss) or after 60s; a `timedOut` error is surfaced to the UI. stdout/stderr are drained concurrently to avoid pipe deadlocks.
- **PATH Auto-Discovery**: Automatically scans `~/.local/bin`, `~/.opencode/bin`, `~/.gemini/antigravity-cli/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, etc.
- **Output Sanitization**: Automatically strips terminal ANSI color escape sequences and Markdown code blocks (` ``` `).

### 6. Dual Capability: Translation & Text Improvement
- **Prompt Mode** (footer checkbox "Prompt", unchecked by default on every popup open): treats the input as an *instruction* instead of text to translate/improve (e.g., "A birthday message for a person called John Doe") and writes the result in the selected **target** language (`buildPrompt(promptMode: true)`); the source-language menu and swap arrow are hidden in this mode.
- **Same-Language (`PT-BR → PT-BR`, `EN-US → EN-US`)**:
  - Automatically switches into **editor/proofreading mode**.
  - Fixes grammar, spelling, punctuation, and syntax while preserving core meaning.
  - UI displays **`Improve & Insert`** with a magic wand icon (`wand.and.stars`).
- **Dialect Conversion (`PT-BR → PT-PT`)**:
  - Converts Brazilian Portuguese syntax and vocabulary into European Portuguese (or vice-versa).
- **Cross-Language (`PT-BR → EN-US`, `Auto → ES-ES`)**:
  - Translates and polishes into the target regional dialect according to the selected tone.

### 7. State & Preferences (`@Observable` & `prefs.toml`)
- Uses modern Swift Observation (`@Observable` from `import Observation`).
- **Do not use `Combine`, `ObservableObject`, or `@Published`**; the codebase uses modern `@Observable` and `@Bindable` to prevent Swift 6 member-import visibility conflicts.
- User preferences (`provider`, `source_language`, `target_language`, `tone`, `auto_paste`, CLI paths) are managed via `~/.config/ghostwriter/prefs.toml`, which is the **source of truth**: keys absent from the file revert to their defaults (deleting a line takes effect). `UserDefaults` is only a fallback when the file is unreadable. Set the `GHOSTWRITER_CONFIG_DIR` environment variable to redirect the config directory (used by the test suite for isolation).
- Clicking the gear icon or menu bar item opens `prefs.toml` directly in the user's text editor. Live file watching via `DispatchSource` reloads preferences automatically upon saving.

### 8. Localization & Strings (`AppStrings.swift` & `Localizable.strings`)
- **No hardcoded user-facing strings in the UI**.
- All strings are defined in `Localizable.strings` under `ghostwriter/Resources/`, localized into the same 16 locales the app can translate (using Apple-canonical `.lproj` codes):
  - `en` (English base, covers en-US), `en-GB`, `pt-BR`, `pt-PT`, `es` (covers es-ES), `es-419` (Latin American Spanish), `fr` (covers fr-FR), `fr-CA`, `de`, `it`, `ja`, `zh-Hans` (Simplified), `zh-Hant` (Traditional), `ru`, `ko`, `nl`.
- Accessed via typed helper `AppStrings` (e.g. `AppStrings.Actions.translateAndInsert`).

---

## Directory Structure

```
ghostwriter/
├── AGENTS.md                            # This guide for AI coding assistants
├── ghostwriter.xcodeproj/               # Xcode project configuration
│   └── project.pbxproj
├── ghostwriter/                         # Main application sources
│   ├── ghostwriterApp.swift             # App entry point & NSApplicationDelegate
│   ├── Models/
│   │   ├── AIProvider.swift             # Supported CLI tools (agy, claude, opencode, custom)
│   │   ├── Language.swift               # Regional languages (pt-BR, pt-PT, en-US, etc.)
│   │   └── LanguageTone.swift           # Tones (Formal, Informal, Concise, Friendly, Academic)
│   ├── Resources/
│   │   ├── AppStrings.swift             # Typed localization accessor
│   │   ├── *.lproj/Localizable.strings  # 16 UI locales mirroring translation targets
│   │   │                                #   (en, en-GB, pt-BR, pt-PT, es, es-419, fr, fr-CA,
│   │   │                                #    de, it, ja, zh-Hans, zh-Hant, ru, ko, nl)
│   │   └── Assets.xcassets              # App icon & accent color
│   ├── Services/
│   │   ├── ActiveAppTracker.swift       # Tracks & reactivates prior focused app
│   │   ├── AITranslationService.swift   # CLI execution & output sanitization
│   │   ├── AppSettings.swift            # @Observable persistent user preferences
│   │   ├── CaretLocator.swift           # Accessibility text cursor bounds locator
│   │   ├── FloatingWindowManager.swift  # Floating panel lifecycle & caret anchoring
│   │   ├── HotKeyManager.swift          # Global ⌃⌘G Carbon event hotkey
│   │   ├── MenuBarManager.swift         # Status bar menu item (show, settings, quit)
│   │   ├── PreferencesManager.swift     # TOML preferences file manager (~/.config/ghostwriter/prefs.toml)
│   │   ├── TextInserter.swift           # Clipboard management & synthetic ⌘V keystrokes
│   │   └── TranslationService.swift     # Core protocol & error definitions
│   └── Views/
│       ├── FloatingPopupView.swift      # Minimal Emoji-picker-style popup interface
│       └── SpeechBubbleShape.swift      # Dynamic conversation bubble shape with arrow
├── ghostwriterTests/                    # Automated unit tests
│   └── ghostwriterTests.swift
└── ghostwriterUITests/                  # UI tests (agent app launch verification)
    └── ghostwriterUITests.swift
```

---

## Critical Project Settings (`project.pbxproj`)

1. **`ENABLE_APP_SANDBOX = NO`**:
   - Must remain **disabled**. A sandboxed macOS app is prohibited by the kernel from sending synthetic `CGEvent` keystrokes (`Command + V`) to other applications.
2. **`INFOPLIST_KEY_LSUIElement = YES`**:
   - Configures the app as an accessory/agent daemon without a standard Dock icon, allowing it to stay resident and trigger on hotkey or status bar icon.
3. **`PBXFileSystemSynchronizedRootGroup`**:
   - The Xcode project uses modern synchronized root groups. Any new Swift files or folders added to `ghostwriter/` or `ghostwriterTests/` are **automatically recognized** without manually modifying the PBX file references.
4. **`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = NO`**:
   - Disabled to avoid indexer conflicts with member visibility. Use `@Observable` for data models.

---

## Build, Test & Run Commands

### 1. Build the Application
```bash
xcodebuild -scheme ghostwriter -destination 'platform=macOS' build
```

### 2. Run Automated Unit Tests
```bash
xcodebuild test -scheme ghostwriter -destination 'platform=macOS' -only-testing:ghostwriterTests
```
*(Always specify `-only-testing:ghostwriterTests` for fast, headless validation. The UI test runner requires an active GUI session and agent lifecycle setup.)*

### 3. Launch App
```bash
open "$(xcodebuild -scheme ghostwriter -destination 'platform=macOS' -showBuildSettings | grep -m1 ' TARGET_BUILD_DIR = ' | awk '{print $3}')/ghostwriter.app"
```

---

## Conventions for Future AI Agents

- **No Hardcoded Strings**: Always add new UI strings to every `<locale>.lproj/Localizable.strings` under `ghostwriter/Resources/` (all 16 locales — see section 8), exposing them through `AppStrings.swift`.
- **State Management**: Use Swift Observation (`@Observable` + `@Bindable`). Avoid introducing `Combine` or `@Published` wrappers.
- **Simplicity First**: Keep the popup window clean, distraction-free, and compact like the macOS Emoji Picker. Do not introduce heavy chrome or complex modal dialogues into `FloatingPopupView`.
- **Preserve System Keystroke Safety**: Always verify that `TextInserter` reactivates the previous application before dispatching synthetic `Command + V` events.
