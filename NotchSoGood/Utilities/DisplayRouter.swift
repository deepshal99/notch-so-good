import AppKit
import ApplicationServices

/// Chooses which display a session's UI belongs on.
///
/// Notifications used to always land on the built-in notch screen, so working on
/// an external display meant looking away to see them. The owning app's focused
/// window tells us where the session actually lives.
///
/// Needs Accessibility access — the same grant the app already asks for to raise
/// windows. Without it this returns nil and callers fall back to the notch
/// screen, i.e. the previous behaviour.
enum DisplayRouter {
    /// The screen showing the terminal/IDE window that owns this session.
    static func screen(sourcePid: pid_t?, sourceBundleId: String?) -> NSScreen? {
        guard let app = owningApp(sourcePid: sourcePid, sourceBundleId: sourceBundleId) else { return nil }
        guard let center = focusedWindowCenter(of: app.processIdentifier) else { return nil }
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private static func owningApp(sourcePid: pid_t?, sourceBundleId: String?) -> NSRunningApplication? {
        if let sourcePid, let app = ProcessTree.owningApp(of: sourcePid), !app.isTerminated {
            return app
        }
        if let bundleId = NotchNotification.nonEmpty(sourceBundleId) {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .first { !$0.isTerminated }
        }
        return nil
    }

    /// Center of the app's focused window in Cocoa global coordinates
    /// (bottom-left origin), or nil without Accessibility access.
    private static func focusedWindowCenter(of pid: pid_t) -> CGPoint? {
        let appElement = AXUIElementCreateApplication(pid)

        guard let window = focusedWindow(of: appElement) else { return nil }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = asValue(positionRef),
              let sizeValue = asValue(sizeRef) else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }

        return cocoaCenter(axOrigin: origin, size: size, primaryHeight: primaryHeight)
    }

    /// Height of the display Cocoa treats as the coordinate-space origin — the
    /// one whose frame starts at (0,0). Accessibility measures Y downward from
    /// the top of *that* screen, even for windows on other displays.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
    }

    /// Convert an Accessibility window rect (top-left origin, Y down) to the
    /// centre point in Cocoa global coordinates (bottom-left origin, Y up).
    ///
    /// Pure so the flip can be verified without a second display attached:
    /// screens above the primary produce negative AX Y, screens to the right
    /// produce AX X beyond the primary's width, and both must survive the flip.
    static func cocoaCenter(axOrigin origin: CGPoint, size: CGSize, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + size.width / 2,
            y: primaryHeight - (origin.y + size.height / 2)
        )
    }

    private static func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let element = asElement(focusedRef) {
            return element
        }
        // Some apps expose no focused window until they're frontmost; the main
        // window, then the first window, are good enough for "which display".
        for attribute in [kAXMainWindowAttribute, kAXWindowsAttribute] {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &ref) == .success else { continue }
            if let element = asElement(ref) { return element }
            if let windows = ref as? [AXUIElement], let first = windows.first { return first }
        }
        return nil
    }

    private static func asElement(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    /// AX attribute values arrive as CFTypeRef; check the real type before casting.
    private static func asValue(_ ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }
}
