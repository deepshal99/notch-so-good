import AppKit
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController
    private let demoController = DemoWindowController()
    /// Track the last known frontmost app so we can yield focus back after URL scheme activates us.
    private var lastFrontmostApp: NSRunningApplication?
    private var frontmostObserver: NSObjectProtocol?

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auto-install hooks on first launch / version update
        NotificationManager.shared.installHooksIfNeeded()

        // Start permission server for approve/deny from the notch
        PermissionServer.shared.start()

        // Global hotkeys: ⌃⌥A approve / ⌃⌥D deny the active permission prompt
        HotkeyManager.shared.start()

        // Poll Claude Code rate-limit windows for the menu bar LIMITS section
        UsageLimitsStore.shared.start()

        Telemetry.shared.trackEvent("app_launched")

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

        // Observe app deactivation to track the last active app before us
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                self?.lastFrontmostApp = app
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let appToRestore = lastFrontmostApp

        for url in urls {
            guard url.scheme == "notchsogood" else { continue }
            handleNotchURL(url)
        }

        // Immediately yield focus back to whatever the user was using
        if let appToRestore, appToRestore.isTerminated == false {
            DispatchQueue.main.async {
                appToRestore.activate()
            }
        }
    }

    private func handleNotchURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value, !value.isEmpty {
                params[item.name] = value
            }
        }

        let sessionId = params["session_id"]

        switch host {
        case "notify":
            let type = NotificationType(rawValue: params["type"] ?? "general") ?? .general
            let message = params["message"] ?? "Claude Code needs your attention"
            let title = params["title"]
            let sourceBundleId = params["source_app"]

            let notification = NotchNotification(
                type: type,
                message: message,
                title: title,
                sessionId: sessionId,
                sourceBundleId: sourceBundleId
            )

            NotificationManager.shared.handleNotification(notification)

        case "session_start":
            let displayName = params["cwd"]
            let sourceBundleId = params["source_app"]
            NotificationManager.shared.startSession(sessionId: sessionId, displayName: displayName, sourceBundleId: sourceBundleId)

        case "session_end":
            // Only end a specific session — ignore if no session_id to prevent wiping all sessions
            if sessionId != nil {
                NotificationManager.shared.endSession(sessionId: sessionId)
            }

        case "demo":
            let animation = params["animation"]
            demoController.open(animation: animation)

        default:
            break
        }
    }
}
