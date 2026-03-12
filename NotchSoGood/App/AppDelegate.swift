import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "notchsogood" else { continue }
            handleNotchURL(url)
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
            NotificationManager.shared.startSession(sessionId: sessionId)

        case "session_end":
            NotificationManager.shared.endSession(sessionId: sessionId)

        default:
            break
        }
    }
}
