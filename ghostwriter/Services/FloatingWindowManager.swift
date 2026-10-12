//
//  FloatingWindowManager.swift
//  ghostwriter
//

import AppKit
import SwiftUI
import Observation

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        // Handle Escape key through the same invalidation path as the popup's
        // key monitor, so an in-flight request can never paste late.
        FloatingWindowManager.shared.cancelAndHide()
    }
}

@Observable
final class FloatingWindowManager {
    static let shared = FloatingWindowManager()
    static let contentSize = NSSize(width: 390, height: 185)
    static let shadowPadding: CGFloat = 8
    static let windowSize = NSSize(
        width: contentSize.width + (shadowPadding * 2),
        height: contentSize.height + (shadowPadding * 2)
    )

    @ObservationIgnored
    private var panel: FloatingPanel?

    @ObservationIgnored
    private var clickOutsideMonitors: [Any] = []

    var isVisible: Bool = false
    var presentationID = UUID()
    /// Invalidated on cancel and on every new show. In-flight requests capture
    /// it at submit time and drop their result if it changed, so late or
    /// cancelled responses never paste or touch newer UI state.
    var requestGeneration = UUID()
    var caretPlacement = CaretPlacement(
        windowOrigin: .zero,
        arrowX: contentSize.width / 2,
        arrowOnTop: true
    )
    var typingContext = TypingContext(selectedText: nil, precedingText: nil)

    func setup() {
        if panel != nil { return }

        let initialRect = NSRect(origin: .zero, size: Self.windowSize)
        let panel = FloatingPanel(contentRect: initialRect)

        let rootView = FloatingPopupView()

        panel.contentView = NSHostingView(rootView: rootView)
        self.panel = panel
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        setup()
        guard let panel = panel else { return }

        ActiveAppTracker.shared.captureCurrentApp()
        AppSettings.shared.reloadFromDisk()

        // Any request still in flight from a previous presentation is stale.
        invalidatePendingRequests()

        // One AX pass captures both the caret placement and the typing context
        // while the target app is still frontmost (before this panel takes focus).
        let snapshot = CaretLocator.captureSnapshot()
        typingContext = snapshot.context
        caretPlacement = CaretLocator.calculatePlacement(
            for: snapshot.caretRect,
            contentSize: Self.contentSize,
            shadowPadding: Self.shadowPadding
        )

        presentationID = UUID()

        panel.setFrame(NSRect(origin: caretPlacement.windowOrigin, size: Self.windowSize), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        isVisible = true

        installClickOutsideMonitors()
    }

    func hide() {
        removeClickOutsideMonitors()
        guard let panel = panel else { return }
        panel.orderOut(nil)
        isVisible = false
    }

    /// Hides the panel AND invalidates in-flight requests (Escape, gear button).
    func cancelAndHide() {
        invalidatePendingRequests()
        hide()
    }

    func invalidatePendingRequests() {
        requestGeneration = UUID()
    }

    /// Whether the given window is this manager's floating panel — used to
    /// decide whether a key event belongs to the popup (and not, say, to an
    /// open menu whose window is something else entirely).
    func owns(_ window: NSWindow?) -> Bool {
        window === panel
    }

    // MARK: - Click-Outside Dismissal

    /// Dismisses the panel when the user clicks anywhere outside it — in other
    /// apps (global monitor) or in this one (local monitor, e.g. menu bar).
    /// Clicks inside the panel pass through untouched.
    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()

        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        })
        if let global {
            clickOutsideMonitors.append(global)
        }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self.panel {
                self.hide()
            }
            return event
        }
        if let local {
            clickOutsideMonitors.append(local)
        }
    }

    private func removeClickOutsideMonitors() {
        clickOutsideMonitors.forEach { NSEvent.removeMonitor($0) }
        clickOutsideMonitors.removeAll()
    }
}
