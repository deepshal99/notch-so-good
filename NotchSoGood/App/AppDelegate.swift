import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController
    private let demoController = DemoWindowController()

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func application(_ application: NSApplication, open urls: [URL]) {
        // Capture the previously active app BEFORE processing URLs,
        // so we can give focus back — URL scheme delivery activates our app.
        let previousApp = NSWorkspace.shared.frontmostApplication

        for url in urls {
            guard url.scheme == "notchsogood" else { continue }
            handleNotchURL(url)
        }

        // Immediately yield focus back to whatever the user was using
        if let previousApp,
           previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async {
                previousApp.activate()
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
            NotificationManager.shared.startSession(sessionId: sessionId, displayName: displayName)

        case "session_end":
            NotificationManager.shared.endSession(sessionId: sessionId)

        case "demo":
            let animation = params["animation"]
            demoController.open(animation: animation)

        default:
            break
        }
    }
}
