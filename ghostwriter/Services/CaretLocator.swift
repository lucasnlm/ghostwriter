//
//  CaretLocator.swift
//  ghostwriter
//

import AppKit
import ApplicationServices

struct CaretPlacement {
    let windowOrigin: NSPoint
    let arrowX: CGFloat
    let arrowOnTop: Bool
}

/// Everything the popup needs from the target app's focused element, captured
/// in a single AX pass while the target app is still frontmost.
struct CaretSnapshot {
    /// Caret/selection rect in AppKit screen coordinates, if resolvable.
    let caretRect: NSRect?
    /// Selection and preceding text from the focused field.
    let context: TypingContext
}

/// Snapshot of what the user is working on in the target app, captured at
/// popup-show time while the target app is still frontmost.
struct TypingContext {
    /// Text currently selected in the target app; pre-fills the popup input.
    let selectedText: String?
    /// Text immediately preceding the selection/caret in the focused field
    /// (length-capped); used as tone/topic context for the AI prompt.
    let precedingText: String?
}

final class CaretLocator {

    /// Bounded budget per AX round trip so a busy or hung target app cannot
    /// freeze the popup (the queries run synchronously on the main thread).
    private static let axMessagingTimeout: Float = 0.5

    /// Finds the target application to query for caret coordinates.
    static func targetApplication() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        if let prev = ActiveAppTracker.shared.previousApp,
           prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            return prev
        }
        return nil
    }

    /// Resolves the currently focused UI element by querying system-wide focus first,
    /// then falling back to the target application's focused hierarchy.
    static func resolveFocusedElement() -> AXUIElement? {
        // 1. Try system-wide focused UI element first
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, axMessagingTimeout)
        var sysFocusedValue: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &sysFocusedValue) == .success,
           let sysFocusedValue = sysFocusedValue {
            // swiftlint:disable:next force_cast
            let element = sysFocusedValue as! AXUIElement
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier {
                return drillDownFocusedElement(element)
            }
        }
        
        // 2. Query target application's focused element
        guard let app = targetApplication() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)
        
        var appFocusedValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &appFocusedValue) == .success,
           let appFocusedValue = appFocusedValue {
            // swiftlint:disable:next force_cast
            let element = appFocusedValue as! AXUIElement
            return drillDownFocusedElement(element)
        }
        
        return nil
    }

    /// Drills down through container elements (e.g. AXWindow, AXSplitGroup, AXScrollArea)
    /// to locate the leaf focused text element.
    private static func drillDownFocusedElement(_ element: AXUIElement) -> AXUIElement {
        var current = element
        AXUIElementSetMessagingTimeout(current, axMessagingTimeout)
        for _ in 0..<4 {
            var childFocused: AnyObject?
            if AXUIElementCopyAttributeValue(current, kAXFocusedUIElementAttribute as CFString, &childFocused) == .success,
               let childFocused = childFocused {
                // swiftlint:disable:next force_cast
                let next = childFocused as! AXUIElement
                if CFEqual(current, next) {
                    break
                }
                current = next
                AXUIElementSetMessagingTimeout(current, axMessagingTimeout)
            } else {
                break
            }
        }
        return current
    }

    /// Checks if a Carbon/Accessibility rectangle represents a valid caret or text selection bounding box.
    /// Note: A blinking cursor insertion point has width == 0 and height > 0, which CoreGraphics CGRect.isEmpty
    /// considers empty, but is completely valid for caret placement.
    static func isValidCaretRect(_ rect: CGRect) -> Bool {
        guard !rect.isNull, !rect.isInfinite else { return false }
        guard rect.origin.x.isFinite, rect.origin.y.isFinite else { return false }
        guard rect.size.height > 0, rect.size.height.isFinite else { return false }
        guard rect.size.width >= 0, rect.size.width.isFinite else { return false }
        return true
    }

    /// Queries bounds for a parameterized range attribute value.
    private static func queryBounds(for rangeValue: AnyObject, in element: AXUIElement) -> CGRect? {
        var boundsValue: AnyObject?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard result == .success, let boundsValue = boundsValue else { return nil }
        
        // swiftlint:disable:next force_cast
        let axBounds = boundsValue as! AXValue
        var cgRect = CGRect.zero
        if AXValueGetValue(axBounds, .cgRect, &cgRect), isValidCaretRect(cgRect) {
            return CGRect(
                x: cgRect.origin.x,
                y: cgRect.origin.y,
                width: max(cgRect.width, 1),
                height: max(cgRect.height, 1)
            )
        }
        return nil
    }

    /// Extracts the text caret or selection bounding box from the focused element.
    /// Includes zero-length range fallbacks for web browsers and custom editors.
    private static func extractCaretFromSelectedTextRange(in element: AXUIElement) -> CGRect? {
        var selectedRangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
              let selectedRangeValue = selectedRangeValue else {
            return nil
        }
        
        // swiftlint:disable:next force_cast
        let rangeAXValue = selectedRangeValue as! AXValue
        var range = CFRange()
        guard AXValueGetValue(rangeAXValue, .cfRange, &range) else {
            return queryBounds(for: rangeAXValue, in: element)
        }
        
        // Attempt 1: Exact range (works for selections and standard AppKit text views)
        if let rect = queryBounds(for: rangeAXValue, in: element) {
            return rect
        }
        
        // Zero-length range fallbacks (for Chromium/WebKit/Electron editors when range length=0 fails)
        if range.length == 0 {
            // Attempt 2: Character at caret (location, 1) -> use leading edge
            var forwardRange = CFRange(location: range.location, length: 1)
            if let charVal = AXValueCreate(.cfRange, &forwardRange),
               let charRect = queryBounds(for: charVal, in: element) {
                return CGRect(x: charRect.minX, y: charRect.minY, width: 1, height: charRect.height)
            }
            
            // Attempt 3: Character before caret (location - 1, 1) -> use trailing edge
            if range.location > 0 {
                var backwardRange = CFRange(location: range.location - 1, length: 1)
                if let charVal = AXValueCreate(.cfRange, &backwardRange),
                   let charRect = queryBounds(for: charVal, in: element) {
                    return CGRect(x: charRect.maxX, y: charRect.minY, width: 1, height: charRect.height)
                }
            }
        }
        
        return nil
    }

    /// Extracts element position and size, used as a fallback for single-line text inputs (e.g. search bars).
    private static func extractElementBounds(in element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posVal = positionValue, let sizeVal = sizeValue else {
            return nil
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        if AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
           // swiftlint:disable:next force_cast
           AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
           size.width > 0, size.height > 0 {
            return CGRect(origin: pos, size: size)
        }
        return nil
    }
    
    /// Extracts the caret (or selection) carbon rect from the focused element,
    /// falling back to element bounds for single-line inputs (e.g. search bars).
    private static func caretCarbonRect(in element: AXUIElement) -> CGRect? {
        // 1. Try to get caret bounds via selected text range
        if let carbonRect = extractCaretFromSelectedTextRange(in: element) {
            return carbonRect
        }

        // 2. Fallback: single-line text inputs (height <= 60pt)
        if let elementBounds = extractElementBounds(in: element), elementBounds.height <= 60 {
            return CGRect(
                x: elementBounds.origin.x + 8,
                y: elementBounds.origin.y,
                width: 1,
                height: elementBounds.height
            )
        }

        return nil
    }

    /// Finds the screen coordinates of the active text caret (cursor) in the frontmost application.
    static func findCaretRect() -> NSRect? {
        guard let element = resolveFocusedElement() else {
            return nil
        }
        return caretCarbonRect(in: element).map { convertCarbonToAppKit($0) }
    }

    /// Single-pass capture of both caret placement and typing context, so the
    /// popup resolves (and can block on) the focused element only once per show.
    static func captureSnapshot(maxContextLength: Int = 2000) -> CaretSnapshot {
        guard let element = resolveFocusedElement() else {
            return CaretSnapshot(caretRect: nil, context: TypingContext(selectedText: nil, precedingText: nil))
        }
        return CaretSnapshot(
            caretRect: caretCarbonRect(in: element).map { convertCarbonToAppKit($0) },
            context: typingContext(in: element, maxContextLength: maxContextLength)
        )
    }

    /// Captures the user's typing context in the target app: the current text
    /// selection (pre-fills the popup) and the text immediately preceding it
    /// (AI context), capped to keep prompts small.
    private static func typingContext(in element: AXUIElement, maxContextLength: Int) -> TypingContext {
        guard let element = resolveFocusedElement() else {
            return TypingContext(selectedText: nil, precedingText: nil)
        }

        var selectedText: String?
        var selectedTextValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let selection = selectedTextValue as? String,
           !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedText = selection
        }

        var precedingText: String?
        var fieldValue: AnyObject?
        var rangeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fieldValue) == .success,
           let fullText = fieldValue as? String,
           AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rangeValue = rangeValue {
            // swiftlint:disable:next force_cast
            let rangeAXValue = rangeValue as! AXValue
            var range = CFRange()
            if AXValueGetValue(rangeAXValue, .cfRange, &range) {
                // AX ranges use UTF-16 offsets, so slice via NSString
                let full = fullText as NSString
                let selectionStart = min(max(0, range.location), full.length)
                let preceding = full.substring(to: selectionStart)
                let capped = preceding.count > maxContextLength
                    ? String(preceding.suffix(maxContextLength))
                    : preceding
                let trimmed = capped.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    precedingText = trimmed
                }
            }
        }

        return TypingContext(selectedText: selectedText, precedingText: precedingText)
    }

    /// Calculates the optimal window placement and arrow position for a specific caret rect (or falls back if nil).
    static func calculatePlacement(
        for caretRect: NSRect?,
        contentSize: NSSize,
        shadowPadding: CGFloat = 8
    ) -> CaretPlacement {
        let gap: CGFloat = 4
        let bubbleWidth = contentSize.width
        let bubbleHeight = contentSize.height

        if let caretRect = caretRect {
            // Anchor to the display the caret is on, not necessarily the main one
            let screen = screen(containing: NSPoint(x: caretRect.midX, y: caretRect.midY))
                ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
            let visibleFrame = screen.visibleFrame

            let caretCenter = caretRect.midX
            
            // Prefer placing below the caret (arrow on top)
            var arrowOnTop = true
            var bubbleTop = caretRect.minY - gap
            var bubbleBottom = bubbleTop - bubbleHeight
            
            // If it would bleed off the bottom of the screen, place above the caret (arrow on bottom)
            if bubbleBottom < visibleFrame.minY {
                bubbleBottom = caretRect.maxY + gap
                bubbleTop = bubbleBottom + bubbleHeight
                arrowOnTop = false
            }
            
            // Ensure bubble does not bleed off top of screen
            if bubbleTop > visibleFrame.maxY {
                bubbleTop = visibleFrame.maxY - 8
                bubbleBottom = bubbleTop - bubbleHeight
            }
            
            // Center horizontally on the caret
            var bubbleX = caretCenter - (bubbleWidth / 2)
            // Clamp to screen edges
            bubbleX = max(visibleFrame.minX + 8, min(visibleFrame.maxX - bubbleWidth - 8, bubbleX))
            
            let windowX = bubbleX - shadowPadding
            let windowY = bubbleBottom - shadowPadding
            
            // Calculate arrow X relative to bubble bounds
            let arrowX = max(24, min(bubbleWidth - 24, caretCenter - bubbleX))
            
            return CaretPlacement(
                windowOrigin: NSPoint(x: windowX, y: windowY),
                arrowX: arrowX,
                arrowOnTop: arrowOnTop
            )
        }
        
        // Fallback 1: Near mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = screen(containing: mouseLocation) ?? NSScreen.main {
            let visibleFrame = mouseScreen.visibleFrame
            if visibleFrame.contains(mouseLocation) {
                var bubbleX = mouseLocation.x - (bubbleWidth / 2)
                bubbleX = max(visibleFrame.minX + 8, min(visibleFrame.maxX - bubbleWidth - 8, bubbleX))

                var arrowOnTop = true
                var bubbleTop = mouseLocation.y - 12
                var bubbleBottom = bubbleTop - bubbleHeight

                if bubbleBottom < visibleFrame.minY {
                    bubbleBottom = mouseLocation.y + 12
                    bubbleTop = bubbleBottom + bubbleHeight
                    arrowOnTop = false
                }

                if bubbleTop > visibleFrame.maxY {
                    bubbleTop = visibleFrame.maxY - 8
                    bubbleBottom = bubbleTop - bubbleHeight
                }

                let windowX = bubbleX - shadowPadding
                let windowY = bubbleBottom - shadowPadding
                let arrowX = max(24, min(bubbleWidth - 24, mouseLocation.x - bubbleX))

                return CaretPlacement(
                    windowOrigin: NSPoint(x: windowX, y: windowY),
                    arrowX: arrowX,
                    arrowOnTop: arrowOnTop
                )
            }
        }

        // Fallback 2: Screen center
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let visibleFrame = screen.visibleFrame
        let bubbleX = visibleFrame.midX - (bubbleWidth / 2)
        let bubbleBottom = visibleFrame.midY - (bubbleHeight / 2) + 40
        let windowX = bubbleX - shadowPadding
        let windowY = bubbleBottom - shadowPadding

        return CaretPlacement(
            windowOrigin: NSPoint(x: windowX, y: windowY),
            arrowX: bubbleWidth / 2,
            arrowOnTop: true
        )
    }

    /// Calculates the optimal window placement and arrow position like the macOS Emoji Picker.
    static func calculatePlacement(
        contentSize: NSSize,
        shadowPadding: CGFloat = 8
    ) -> CaretPlacement {
        calculatePlacement(for: findCaretRect(), contentSize: contentSize, shadowPadding: shadowPadding)
    }

    /// Computes squared Euclidean distance from a point to a rectangle.
    private static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Returns the screen whose frame contains the given global (AppKit) point,
    /// or the nearest screen if the point is slightly outside bounds.
    private static func screen(containing point: NSPoint) -> NSScreen? {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        return NSScreen.screens.min(by: { s1, s2 in
            distanceSquared(from: point, to: s1.frame) < distanceSquared(from: point, to: s2.frame)
        })
    }
    
    /// Convenience method for backwards compatibility with tests and callers passing a single window size.
    static func calculatePlacement(forWindowSize windowSize: NSSize) -> CaretPlacement {
        calculatePlacement(contentSize: windowSize, shadowPadding: 0)
    }
    
    /// Converts a Carbon (top-left origin) rectangle into AppKit (bottom-left origin) screen coordinates.
    static func convertCarbonToAppKit(_ rect: CGRect) -> NSRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return NSRect(origin: rect.origin, size: rect.size)
        }
        let screenHeight = primaryScreen.frame.height
        let appKitY = screenHeight - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: appKitY, width: max(rect.width, 1), height: max(rect.height, 1))
    }
}
