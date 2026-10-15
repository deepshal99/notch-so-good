import AppKit
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
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsWindowController.shared.updater = updaterController.updater
        MenuBarController.shared.install()
        // Auto-install hooks on first launch / version update
        NotificationManager.shared.installHooksIfNeeded()

        // Start permission server for approve/deny from the notch
        PermissionServer.shared.start()

        // Global hotkeys: ⌃⌥A approve / ⌃⌥D deny the active permission prompt
        HotkeyManager.shared.start()

        // Poll Claude Code rate-limit windows for the menu bar LIMITS section
        UsageLimitsStore.shared.start()
        // Compile the character shader now so the first notification shows it instantly.
        CharacterRenderer.shared.prepare(warm: [(CharacterSettings.shared.kind, CharacterSettings.shared.finish)])

        Telemetry.shared.trackEvent("app_launched")

        // First run: say hello from the notch, so a new install shows where it
        // lives and what it does instead of sitting silent until a session starts.
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let name = CharacterSettings.shared.kind.displayName
                NotificationManager.shared.handleNotification(NotchNotification(
                    type: .general,
                    message: "I'll watch your Claude Code and Codex sessions and tap you when one needs you. Your usage lives in the menu bar.",
                    title: "Hi, I'm \(name)"
                ))
            }
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
}
