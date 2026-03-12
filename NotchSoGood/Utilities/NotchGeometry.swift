import AppKit

struct NotchGeometry {
    /// Width of the physical notch
    let notchWidth: CGFloat
    /// Height of the safe area inset (notch + menubar area)
    let notchHeight: CGFloat
    /// Center X of the screen (and notch)
    let centerX: CGFloat
    /// Top Y of the screen in macOS coordinates (origin bottom-left)
    let screenTopY: CGFloat
    /// Full screen frame
    let screenFrame: NSRect

    /// Calculate notch geometry for the screen with the notch (or the main screen).
    /// Checks all screens so it works on multi-display setups where the notch screen isn't .main.
    static func calculate() -> NotchGeometry? {
        // Prefer the screen that actually has a notch
        let screen = notchScreen ?? NSScreen.main
        guard let screen else { return nil }
        let safeTop = screen.safeAreaInsets.top
        guard safeTop > 0 else { return nil }

        let frame = screen.frame
        let leftArea = screen.auxiliaryTopLeftArea ?? .zero
        let rightArea = screen.auxiliaryTopRightArea ?? .zero
        let notchWidth = frame.width - leftArea.width - rightArea.width

        return NotchGeometry(
            notchWidth: notchWidth,
            notchHeight: safeTop,
            centerX: frame.midX,
            screenTopY: frame.maxY,
            screenFrame: frame
        )
    }

    /// Fallback origin for Macs without a notch — positions below the menu bar, centered.
    static func fallbackOrigin() -> (x: CGFloat, y: CGFloat, menubarHeight: CGFloat) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return (0, 0, 24) }
        let menubarHeight: CGFloat = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
        return (screen.frame.midX, screen.frame.maxY - menubarHeight, menubarHeight)
    }

    static var hasNotch: Bool {
        notchScreen != nil
    }

    /// Find the screen that has a physical notch (safeAreaInsets.top > 0).
    private static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }
}
