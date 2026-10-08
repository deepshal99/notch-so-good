import SwiftUI

@main
struct NotchSoGoodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // The menu bar item and its panel are ours (MenuBarController). SwiftUI's
    // App still needs a scene; a menu bar extra that's never inserted creates
    // no window and no item (an empty Settings scene opened a blank window
    // whenever the app activated).
    var body: some Scene {
        MenuBarExtra("Notch So Good", isInserted: .constant(false)) { EmptyView() }
    }
}

/// Template glyphs drawn in code so they stay crisp at any scale: Peek holding
/// on to the notch's edge with two little arms. Laid out on a half-point grid
/// so every edge lands on a Retina pixel.
enum MenuBarGlyph {
    static let normal = make(attention: false)
    static let attention = make(attention: true)

    private static func make(attention: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            func rounded(_ r: CGRect, _ radius: CGFloat) {
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }

            // Two arms reaching up to the menu bar's edge (the notch it hangs from).
            rounded(CGRect(x: 6.5, y: 0, width: 1.5, height: 5.5), 0.75)
            rounded(CGRect(x: 13, y: 0, width: 1.5, height: 5.5), 0.75)
            // The body: a soft rounded block.
            rounded(CGRect(x: 4, y: 3.5, width: 13, height: 11.5), 5)
            ctx.fillPath()

            // Eyes, punched out.
            ctx.setBlendMode(.clear)
            rounded(CGRect(x: 7.5, y: 7, width: 2, height: 4.5), 1)
            rounded(CGRect(x: 11.5, y: 7, width: 2, height: 4.5), 1)
            ctx.fillPath()

            if attention {
                // A dot at the shoulder, with a clear gap so it reads at menu bar size.
                ctx.addEllipse(in: CGRect(x: 14.5, y: 9, width: 7.5, height: 7.5))
                ctx.fillPath()
                ctx.setBlendMode(.normal)
                ctx.addEllipse(in: CGRect(x: 16, y: 10.5, width: 4.5, height: 4.5))
                ctx.fillPath()
            }
            return true
        }
        // Template so it follows the menu bar's tint. The dot is part of the
        // glyph: a second colour would break template rendering.
        image.isTemplate = true
        return image
    }
}
