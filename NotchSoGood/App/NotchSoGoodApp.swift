import SwiftUI

@main
struct NotchSoGoodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarSettingsView(
                notificationManager: NotificationManager.shared,
                updater: appDelegate.updaterController.updater
            )
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar label — pixel Chawd, with an amber dot when a session is waiting on the user.
struct MenuBarIconView: View {
    @ObservedObject private var manager = NotificationManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: ChawdMenuBarIcon.shared)
            if manager.needsAttention {
                Circle()
                    .fill(Color(hex: "FBBF24"))
                    .frame(width: 5, height: 5)
                    .offset(x: 1, y: -1)
            }
        }
    }
}

/// Renders a tiny pixel-art Chawd as a template NSImage for the menu bar.
enum ChawdMenuBarIcon {
    static let shared: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let px: CGFloat = 1.25
            let gridW: CGFloat = 14 * px
            let gridH: CGFloat = 13 * px
            let ox = (rect.width - gridW) / 2
            let oy = (rect.height - gridH) / 2

            NSColor.black.setFill()

            // Left arm/claw stub
            NSRect(x: ox, y: oy + 2 * px, width: 2 * px, height: 4 * px).fill()

            // Main body
            NSRect(x: ox + 2 * px, y: oy + 0 * px, width: 10 * px, height: 7 * px).fill()

            // Left leg
            NSRect(x: ox + 4 * px, y: oy + 7 * px, width: 2 * px, height: 3.5 * px).fill()

            // Right leg
            NSRect(x: ox + 8.5 * px, y: oy + 7 * px, width: 2 * px, height: 3.5 * px).fill()

            // Eyes — punch out as transparent
            NSColor.clear.setFill()
            NSRect(x: ox + 5 * px, y: oy + 2 * px, width: 1 * px, height: 2.5 * px).fill(using: .copy)
            NSRect(x: ox + 8.5 * px, y: oy + 2 * px, width: 1 * px, height: 2.5 * px).fill(using: .copy)

            return true
        }
        image.isTemplate = true
        return image
    }()
}
