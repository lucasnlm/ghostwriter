//
//  FloatingPopupView.swift
//  ghostwriter
//

import SwiftUI
import AppKit
import Observation
import Carbon.HIToolbox

struct FloatingPopupView: View {
    @Bindable var settings = AppSettings.shared
    var windowManager = FloatingWindowManager.shared

    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var keyMonitor: Any?
    @State private var submitTask: Task<Void, Never>?
    @State private var isPromptMode: Bool = false
    @FocusState private var isFocused: Bool

    private var isImprovementMode: Bool {
        settings.sourceLanguage == settings.targetLanguage
    }

    private var placeholderText: String {
        if isPromptMode {
            return AppStrings.Placeholders.promptMode
        } else if isImprovementMode {
            return AppStrings.Placeholders.improve(targetName: settings.targetLanguage.displayName)
        } else {
            return AppStrings.Placeholders.translate(sourceName: settings.sourceLanguage.displayName)
        }
    }

    private var statusText: String {
        if isPromptMode {
            return AppStrings.Status.generating(targetName: settings.targetLanguage.displayName)
        } else if isImprovementMode {
            return AppStrings.Status.improving(targetName: settings.targetLanguage.displayName)
        } else {
            return AppStrings.Status.translating(targetName: settings.targetLanguage.displayName)
        }
    }

    private var submitIconName: String {
        if isPromptMode { return "square.and.pencil" }
        return isImprovementMode ? "wand.and.stars" : "arrow.up.circle.fill"
    }

    private var submitLabel: String {
        if isPromptMode { return AppStrings.Actions.writeAndInsert }
        return isImprovementMode ? AppStrings.Actions.improveAndInsert : AppStrings.Actions.translateAndInsert
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar (compact pills)
            headerBar

            Divider()
                .opacity(0.25)

            // Text Input Area
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(placeholderText)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary.opacity(0.65))
                        Text(AppStrings.Placeholders.shortcutHint)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.45))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
                }

                TextEditor(text: editorTextBinding)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 0)
                    .padding(.top, 0)
                    .focused($isFocused)
                    .disabled(isLoading)
            }
            .frame(maxHeight: .infinity)

            // Error Banner (if error occurred)
            if let error = errorMessage {
                errorBanner(error: error)
            }

            Divider()
                .opacity(0.25)

            // Footer Bar
            footerBar
        }
        .padding(.top, windowManager.caretPlacement.arrowOnTop ? 14 : 10)
        .padding(.bottom, windowManager.caretPlacement.arrowOnTop ? 10 : 14)
        .padding(.horizontal, 14)
        .frame(width: FloatingWindowManager.contentSize.width, height: FloatingWindowManager.contentSize.height)
        .background(
            ZStack {
                SpeechBubbleShape(
                    arrowX: windowManager.caretPlacement.arrowX,
                    arrowOnTop: windowManager.caretPlacement.arrowOnTop
                )
                .fill(.ultraThinMaterial)

                SpeechBubbleShape(
                    arrowX: windowManager.caretPlacement.arrowX,
                    arrowOnTop: windowManager.caretPlacement.arrowOnTop
                )
                .fill(bubbleTint)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
        )
        .overlay(
            SpeechBubbleShape(
                arrowX: windowManager.caretPlacement.arrowX,
                arrowOnTop: windowManager.caretPlacement.arrowOnTop
            )
            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .padding(FloatingWindowManager.shadowPadding)
        .frame(width: FloatingWindowManager.windowSize.width, height: FloatingWindowManager.windowSize.height)
        .onAppear {
            resetAndFocus()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: windowManager.presentationID) {
            resetAndFocus()
        }
        .onChange(of: windowManager.isVisible) { _, visible in
            // Tie the monitor lifecycle to real panel visibility: onDisappear
            // is unreliable for an ordered-out panel whose hosting view persists.
            if visible {
                installKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                // Release keyboard focus so the editor no longer accepts
                // typed input while a request is in flight
                isFocused = false
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            // Source Language Menu & Swap (hidden in Prompt mode — the source language is irrelevant)
            if !isPromptMode {
                Menu {
                    ForEach(Language.sourceLanguages) { lang in
                        Button(lang.displayName) {
                            settings.sourceLanguage = lang
                        }
                    }
                } label: {
                    Text(settings.sourceLanguage.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Swap Arrow
                Button(action: swapLanguages) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isImprovementMode ? .secondary.opacity(0.4) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(settings.sourceLanguage == .auto || isImprovementMode)
                .help(settings.sourceLanguage == .auto || isImprovementMode ? AppStrings.Actions.swapUnavailable : AppStrings.Actions.swapLanguages)
            }

            // Target Language Menu
            Menu {
                ForEach(Language.targetLanguages) { lang in
                    Button(lang.displayName) {
                        settings.targetLanguage = lang
                    }
                }
            } label: {
                Text(settings.targetLanguage.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Tone Menu
            Menu {
                ForEach(LanguageTone.allCases) { tone in
                    Button(tone.displayName) {
                        settings.selectedTone = tone
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.2")
                        .font(.system(size: 9))
                    Text(settings.selectedTone.displayName)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Settings Button
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(AppStrings.Actions.settings)
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text(AppStrings.Keys.commandReturn)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)

                    Image(systemName: submitIconName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(submitLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text(AppStrings.Keys.escape)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)

                    Text(AppStrings.Actions.close)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Prompt mode: input becomes an instruction, answered in the target language
            Toggle(isOn: $isPromptMode) {
                Text(AppStrings.Actions.promptMode)
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.checkbox)
            .fixedSize()
            .help(AppStrings.Actions.promptModeHelp)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 10))
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            Button(AppStrings.Actions.settings, action: openSettings)
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            SpeechBubbleShape(
                arrowX: windowManager.caretPlacement.arrowX,
                arrowOnTop: windowManager.caretPlacement.arrowOnTop
            )
            .fill(Color.black.opacity(0.3))

            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
        }
        .transition(.opacity)
    }

    // MARK: - Helpers & Actions

    /// Binding that discards edits while a request is in flight, guaranteeing
    /// the input cannot change mid-translation even if keyboard events slip
    /// past the disabled control.
    private var editorTextBinding: Binding<String> {
        Binding<String>(
            get: { inputText },
            set: { newValue in
                guard !isLoading else { return }
                inputText = newValue
            }
        )
    }

    /// Theme-aware tint layered over the ultra-thin material: pushes the
    /// bubble toward bright white in light mode and deep charcoal in dark
    /// mode, so it reads clean instead of gray while keeping vibrancy.
    private var bubbleTint: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkAppearances: [NSAppearance.Name] = [
                .darkAqua,
                .accessibilityHighContrastDarkAqua,
                .vibrantDark
            ]
            let isDark = appearance.bestMatch(from: darkAppearances) != nil
            return isDark
                ? NSColor.black.withAlphaComponent(0.35)
                : NSColor.white.withAlphaComponent(0.55)
        })
    }

    private func resetAndFocus() {
        // A new presentation supersedes anything still in flight.
        submitTask?.cancel()
        // Pre-fill with the text selected in the target app, if any
        inputText = windowManager.typingContext.selectedText ?? ""
        // Prompt mode is opt-in per invocation, unchecked by default
        isPromptMode = false
        errorMessage = nil
        isLoading = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
    }

    private func swapLanguages() {
        guard settings.sourceLanguage != .auto, !isImprovementMode else { return }
        let temp = settings.sourceLanguage
        settings.sourceLanguage = settings.targetLanguage
        settings.targetLanguage = temp
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only intercept keys destined for the popup itself; when a menu is
            // open its window is a different one, so Esc closes just the menu.
            guard self.windowManager.isVisible, self.windowManager.owns(event.window) else { return event }

            // Check for Command + Return (Enter)
            if event.keyCode == UInt16(kVK_Return), event.modifierFlags.contains(.command) {
                if !self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.isLoading {
                    self.submitTranslation()
                    return nil
                }
            }
            // Check for Command + P (toggles the Prompt-mode checkbox)
            if event.keyCode == UInt16(kVK_ANSI_P), event.modifierFlags.contains(.command) {
                if !self.isLoading {
                    self.isPromptMode.toggle()
                }
                return nil
            }
            // Check for Escape
            if event.keyCode == UInt16(kVK_Escape) {
                self.cancelAndHide()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Dismisses the popup and invalidates any in-flight translation request,
    /// so its late result is never pasted or shown.
    private func cancelAndHide() {
        submitTask?.cancel()
        windowManager.cancelAndHide()
    }

    private func submitTranslation() {
        let textToTranslate = inputText
        guard !textToTranslate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        errorMessage = nil
        isLoading = true

        let generation = windowManager.requestGeneration
        let source = settings.sourceLanguage
        let target = settings.targetLanguage
        let tone = settings.selectedTone
        let context = windowManager.typingContext.precedingText
        let promptMode = isPromptMode

        submitTask = Task {
            do {
                let translated = try await AITranslationService.shared.translate(
                    text: textToTranslate,
                    sourceLanguage: source,
                    targetLanguage: target,
                    tone: tone,
                    context: context,
                    promptMode: promptMode
                )

                // A stale result (cancelled via Esc, superseded by a retry, or a
                // newer popup presentation) must not touch newer UI state.
                guard windowManager.requestGeneration == generation else { return }
                isLoading = false
                windowManager.hide()

                // Insert into previous application at the caret
                await TextInserter.shared.insertText(translated)
            } catch {
                // Cancellation or a superseding request: nothing to show.
                guard windowManager.requestGeneration == generation else { return }
                isLoading = false
                errorMessage = error.localizedDescription
                // Focus back so the user can correct the text and retry
                isFocused = true
            }
        }
    }

    private func openSettings() {
        windowManager.cancelAndHide()
        PreferencesManager.shared.openPreferencesFile()
    }
}
