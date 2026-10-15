import Foundation
import Aptabase

/// Anonymous counts, nothing more: how many people installed the app, how many
/// had it open on a given day, and how many used it with an agent that day.
///
/// - No identifiers of any kind (no install id, no user id), no file paths, no
///   project names, no prompts, no commands. Aptabase adds only the app
///   version, macOS version and locale, and doesn't store IP addresses.
/// - Each daily count is sent at most once per day per Mac.
/// - Off with Settings → About → "Share anonymous usage data".
/// - A no-op until a key is set (`AptabaseAppKey` in Info.plist, filled in by
///   the release build from `APTABASE_APP_KEY`).
@MainActor
final class Telemetry {
    static let shared = Telemetry()

    private let isConfigured: Bool

    private init() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "AptabaseAppKey") as? String,
              !key.isEmpty else {
            isConfigured = false
            return
        }
        Aptabase.shared.initialize(appKey: key)
        isConfigured = true
    }

    /// Counts are only marked as sent when they really are.
    private var canSend: Bool { isConfigured && NotificationManager.shared.telemetryEnabled }

    /// `install` once ever, `active_day` once a day.
    func noteLaunch() {
        guard canSend else { return }
        if !UserDefaults.standard.bool(forKey: "telemetry.sent.installed") {
            UserDefaults.standard.set(true, forKey: "telemetry.sent.installed")
            trackEvent("install")
        }
        once(per: "active_day")
    }

    /// `session_day` once a day, with which agent ("claude" / "codex"), the
    /// first time a session shows up that day.
    func noteSession(agent: AgentSource) {
        once(per: "session_day", props: ["agent": agent.rawValue])
    }

    private func once(per event: String, props: [String: Any] = [:]) {
        guard canSend else { return }
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let key = "telemetry.sent.\(event)"
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        trackEvent(event, props: props)
    }

    /// Track an event, if telemetry is configured and the user hasn't opted out.
    func trackEvent(_ name: String, props: [String: Any] = [:]) {
        guard isConfigured, NotificationManager.shared.telemetryEnabled else { return }
        Aptabase.shared.trackEvent(name, with: props)
    }
}
