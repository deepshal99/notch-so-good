import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Where to draw on a given screen.
///
/// Every screen gets geometry, not just the one with a notch — that's what lets
/// a session's notification appear on the display it's actually running on.
/// Screens without a notch hang their panel just below the menu bar instead of
/// merging with a bezel.
struct NotchGeometry {
    /// True when this screen physically has a notch to blend into.
    let hasNotch: Bool
    /// Width of the physical notch; 0 on screens without one.
    let notchWidth: CGFloat
    /// Height of the black bar the pill lives in — the notch's safe-area inset,
    /// or a nominal pill height on screens without a notch.
    let barHeight: CGFloat
    /// Center X of the screen (and of the notch).
    let centerX: CGFloat
    /// The Y panels hang from: the screen's top edge on a notched screen, or
    /// just below the menu bar elsewhere.
    let topY: CGFloat
    let screenFrame: NSRect
    let displayID: CGDirectDisplayID

    /// Nominal pill height on screens with no notch to match.
    private static let floatingBarHeight: CGFloat = 28

    static func geometry(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top

        if safeTop > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let width = frame.width - leftArea.width - rightArea.width
            if width > 0, width < frame.width {
                return NotchGeometry(
                    hasNotch: true,
                    notchWidth: width,
                    barHeight: safeTop,
                    centerX: frame.midX,
                    topY: frame.maxY,
                    screenFrame: frame,
                    displayID: screen.displayID
                )
            }
        }

        // No notch: sit below the menu bar as a free-floating pill.
        let menuBarHeight = max(24, frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(
            hasNotch: false,
            notchWidth: 0,
            barHeight: floatingBarHeight,
            centerX: frame.midX,
            topY: frame.maxY - menuBarHeight,
            screenFrame: frame,
            displayID: screen.displayID
        )
    }

    /// The screen that physically has a notch, if any.
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static var hasNotch: Bool { notchScreen != nil }

    /// Geometry for the notch screen, falling back to the main display.
    /// This is the default target when we can't tell where a session lives.
    static func calculate() -> NotchGeometry? {
        guard let screen = notchScreen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        return geometry(for: screen)
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }
}
