import SwiftUI

@main
struct NotchSoGoodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(notificationManager: NotificationManager.shared)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(notificationManager: NotificationManager.shared, updater: appDelegate.updaterController.updater)
        }
    }
}

/// Menu bar label: Peek hanging from a sliver of notch, with an orange dot
/// when a session is waiting on the user.
struct MenuBarIconView: View {
    @ObservedObject private var manager = NotificationManager.shared

    var body: some View {
        Image(nsImage: manager.needsAttention ? MenuBarGlyph.attention : MenuBarGlyph.normal)
            .accessibilityLabel(manager.needsAttention ? "Notch So Good, a session needs you" : "Notch So Good")
    }
}

/// Template glyphs drawn in code so they stay crisp at any scale.
enum MenuBarGlyph {
    static let normal = make(attention: false)
    static let attention = make(attention: true)

    private static func make(attention: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)

            // The notch: a bar the body hangs out of.
            ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: 1.5, width: 14, height: 2.4), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
            ctx.fillPath()

            // Peek's body: square where it meets the notch, soft at the bottom.
            let body = CGMutablePath()
            let (l, r, t, b, rad): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (4.5, 13.5, 3, 13.6, 4)
            body.move(to: CGPoint(x: l, y: t))
            body.addLine(to: CGPoint(x: r, y: t))
            body.addLine(to: CGPoint(x: r, y: b - rad))
            body.addQuadCurve(to: CGPoint(x: r - rad, y: b), control: CGPoint(x: r, y: b))
            body.addLine(to: CGPoint(x: l + rad, y: b))
            body.addQuadCurve(to: CGPoint(x: l, y: b - rad), control: CGPoint(x: l, y: b))
            body.closeSubpath()
            ctx.addPath(body)
            ctx.fillPath()

            // Eyes, punched out.
            ctx.setBlendMode(.clear)
            for x in [7.4, 10.6] {
                ctx.addPath(CGPath(roundedRect: CGRect(x: x - 0.8, y: 6.4, width: 1.6, height: 3.4), cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
            }
            ctx.fillPath()

            if attention {
                // A dot beside the body, with a gap cut so it reads at menu bar size.
                ctx.addEllipse(in: CGRect(x: 13.4, y: 8.4, width: 6.4, height: 6.4))
                ctx.fillPath()
                ctx.setBlendMode(.normal)
                ctx.addEllipse(in: CGRect(x: 14.4, y: 9.4, width: 4.4, height: 4.4))
                ctx.fillPath()
            }
            return true
        }
        // Template so it follows the menu bar's light/dark tint. The dot is part of
        // the glyph (an extra colour would break template rendering).
        image.isTemplate = true
        return image
    }
}
