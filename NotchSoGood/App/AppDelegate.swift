import AppKit
import ServiceManagement
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController

    override init() {
        #if DEBUG
        DebugSnapshots.runIfRequested()
        #endif
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: Updates.shared,
            userDriverDelegate: Updates.shared
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsWindowController.shared.updater = updaterController.updater
        Updates.shared.updater = updaterController.updater
        MenuBarController.shared.install()
        // Auto-install hooks on first launch / version update
        NotificationManager.shared.installHooksIfNeeded()
        HookGuard.shared.start()

        // Start permission server for approve/deny from the notch
        PermissionServer.shared.start()

        // Global hotkeys: ⌃⌥A approve / ⌃⌥D deny the active permission prompt
        HotkeyManager.shared.start()

        // Poll Claude Code rate-limit windows for the menu bar LIMITS section
        UsageLimitsStore.shared.start()
        // Compile the character shader now so the first notification shows it instantly.
        CharacterRenderer.shared.prepare(warm: [(CharacterSettings.shared.kind, CharacterSettings.shared.finish)])

        Telemetry.shared.noteLaunch()
        Self.setUpLoginItem()

        // First run: a short practice tour in the notch, so a new install shows
        // where it lives and how to use it, by doing.
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Tour.shared.start() }
        }

        // Hide/restore the pill when spaces change (fullscreen apps hide the menu bar)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NotificationManager.shared.windowController.handleSpaceChange()
            }
        }

        // Reposition notch panels when displays change (monitor swap, resolution change)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NotificationManager.shared.windowController.handleScreenChange()
            }
        }
    }

    /// Open at login is on from the first launch (a menu bar coworker that
    /// doesn't come back after a restart isn't much of one); Settings turns it
    /// off. Installers before 4.7 added their own LaunchAgent for this, which
    /// would open a second copy: it goes.
    private static func setUpLoginItem() {
        let legacy = NSHomeDirectory() + "/Library/LaunchAgents/com.notchsogood.app.plist"
        if FileManager.default.fileExists(atPath: legacy) {
            try? FileManager.default.removeItem(atPath: legacy)
        }
        guard !UserDefaults.standard.bool(forKey: "loginItemConfigured") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }
}
