<p align="center">
  <img src="docs/icon.png" width="180" alt="Ghostwriter app icon" />
</p>

<h1 align="center">Ghostwriter</h1>

<p align="center">
  A native macOS quick-translation &amp; writing assistant that lives in a speech bubble at your caret.<br/>
  Press <kbd>⌃</kbd><kbd>⌘</kbd><kbd>G</kbd> anywhere. Type. Hit <kbd>⌘⏎</kbd>. Keep writing.
</p>

---

Ghostwriter brings the emoji-picker experience to translation. Press the hotkey in any app — Slack, Notes, Chrome, Xcode — and a floating glass bubble appears right beneath your caret. Write in any language: cross-language pairs get translated, and when source and target match, it proofreads and polishes instead. Hit <kbd>⌘⏎</kbd> and the result is inserted directly at your cursor.

## Features

- **Caret-anchored bubble** — pops up right where you're typing, in any app
- **Translate or improve** — same-language pairs switch to proofreading automatically
- **16 languages with dialects** — `pt-BR` vs `pt-PT`, `en-US` vs `en-GB`, `es-ES` vs `es-419`, … plus auto-detect
- **5 tones** — Formal, Informal, Concise, Friendly, Academic
- **Zero API keys** — runs the AI CLIs you already have (`agy`, `claude`, `opencode`, or any custom binary)
- **Menu bar resident** — no Dock icon, no accounts, fully configurable via `prefs.toml`

## Get started

You'll need macOS 26.6+, [Xcode](https://developer.apple.com/xcode/), and one AI CLI ([`agy`](https://antigravity.google), [`claude`](https://claude.com/claude-code), or [`opencode`](https://opencode.ai)).

Open `ghostwriter.xcodeproj` and press <kbd>⌘R</kbd> — or build from the terminal:

```bash
xcodebuild -scheme ghostwriter -destination 'platform=macOS' build
```

On first launch, grant the **Accessibility** permission when prompted — it's needed to find your caret and insert text.

## Configuration

Everything lives in `~/.config/ghostwriter/prefs.toml` (the gear icon in the popup opens it). Saving reloads instantly — even the hotkey re-registers on the fly.

```toml
shortcut = "ctrl+cmd+g"     # global hotkey
provider = "agy"            # agy | claude | opencode | custom
source_language = "pt-BR"   # or "auto"
target_language = "en-US"
tone = "formal"             # formal | informal | concise | friendly | academic
auto_paste = true
```

CLI binaries are auto-discovered on your `PATH`; see the comments in the file for explicit paths and the `custom` provider's `{prompt}` template.

## Development

```bash
xcodebuild test -scheme ghostwriter -destination 'platform=macOS' -only-testing:ghostwriterTests
```

Architecture and conventions are documented in [AGENTS.md](AGENTS.md). Icon source: [`.icon-design/icon.svg`](.icon-design/icon.svg).
