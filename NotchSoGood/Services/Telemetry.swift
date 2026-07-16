import Foundation
import Aptabase

/// Thin, privacy-first wrapper around Aptabase (open-source, EU-hostable analytics).
///
/// - Fully opt-out: gated behind `NotificationManager.shared.telemetryEnabled`.
/// - Fully no-op if no app key is configured (Info.plist has no "AptabaseAppKey"
///   entry by default — that's intentional until a key is issued).
/// - Never tracks message contents, file paths, session IDs, or anything else
///   that could identify a user or their work. Event names and small enum-like
///   properties only.
@MainActor
final class Telemetry {
    static let shared = Telemetry()

    /// True only when a non-empty app key was found and Aptabase initialized successfully.
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

    /// Track an event, if telemetry is configured and the user hasn't opted out.
    /// Safe to call unconditionally from anywhere — this is a no-op otherwise.
    func trackEvent(_ name: String, props: [String: Any] = [:]) {
        guard isConfigured, NotificationManager.shared.telemetryEnabled else { return }
        Aptabase.shared.trackEvent(name, with: props)
    }
}
