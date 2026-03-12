import SwiftUI

@main
struct NotchSoGoodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Notch So Good", systemImage: "sparkle") {
            MenuBarSettingsView(notificationManager: NotificationManager.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
