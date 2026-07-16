import Foundation
import Security

/// Live Claude Code rate-limit status for the menu bar — mirrors the iOS
/// "Limits" widget. Reads the Claude Code OAuth token from the login Keychain
/// and polls the (undocumented) usage endpoint that powers `/usage` in the CLI:
/// GET https://api.anthropic.com/api/oauth/usage
/// → {"five_hour":{"utilization":37.0,"resets_at":"ISO8601"},"seven_day":{...},
///    "seven_day_opus":{...}, ...} where utilization is percent used (0–100).
/// Everything is best-effort: any failure quietly clears the windows.
@MainActor
final class UsageLimitsStore: ObservableObject {
    static let shared = UsageLimitsStore()

    struct LimitWindow: Identifiable {
        let label: String        // "Session", "Weekly", "Weekly · Opus", ...
        let percentLeft: Int     // 0–100
        let resetsAt: Date?
        var id: String { label }
    }

    @Published var windows: [LimitWindow] = []
    @Published var lastUpdated: Date?

    private var refreshTimer: Timer?
    private var lastFetchAt: Date?
    private var isFetching = false
    /// resets_at values we've already alerted for — one low-limit nudge per window.
    private var alertedResetKeys: Set<String> = []

    private static let minRefreshInterval: TimeInterval = 5 * 60
    private static let autoRefreshInterval: TimeInterval = 10 * 60

    private init() {}

    /// Kick off the first fetch and a 10-minute auto-refresh cycle.
    func start() {
        refresh(force: true)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.autoRefreshInterval, repeats: true) { _ in
            Task { @MainActor in
                UsageLimitsStore.shared.refresh()
            }
        }
    }

    func refresh(force: Bool = false) {
        guard !isFetching else { return }
        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < Self.minRefreshInterval {
            return
        }
        lastFetchAt = Date()
        isFetching = true

        Task { [weak self] in
            // Runs off the main actor — first Keychain read may prompt once.
            let fetched = await Self.fetchWindows()
            guard let self else { return }
            self.isFetching = false
            if let fetched {
                self.windows = fetched
                self.lastUpdated = Date()
                self.checkLowSessionLimit()
            } else {
                self.windows = []
            }
        }
    }

    // MARK: - Low-limit warning

    private func checkLowSessionLimit() {
        guard let session = windows.first(where: { $0.label == "Session" }),
              session.percentLeft < 10 else { return }
        // Dedupe on the reset timestamp so we fire once per 5-hour window.
        let key = session.resetsAt.map { String($0.timeIntervalSince1970) } ?? "unknown"
        guard !alertedResetKeys.contains(key) else { return }
        alertedResetKeys.insert(key)

        let countdown = session.resetsAt.map { Self.resetCountdown($0) } ?? "soon"
        NotificationManager.shared.handleNotification(NotchNotification(
            type: .general,
            message: "Session limit almost used — resets in \(countdown)",
            title: "Limits"
        ))
    }

    // MARK: - Formatting

    /// "4h 30m" / "45m" countdown until a window resets.
    static func resetCountdown(_ date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Fetch (off main actor)

    nonisolated private static func fetchWindows() async -> [LimitWindow]? {
        guard let token = loadAccessToken(),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // Without a claude-code User-Agent the endpoint 429s aggressively.
        request.setValue("claude-code/2.0.0 (external; NotchSoGood)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return parseWindows(json)
        } catch {
            return nil
        }
    }

    // MARK: - Token

    /// Claude Code stores OAuth creds as a generic password in the login
    /// Keychain (service "Claude Code-credentials"); older installs may use
    /// ~/.claude/.credentials.json. Both hold {"claudeAiOauth":{"accessToken":...}}.
    nonisolated private static func loadAccessToken() -> String? {
        var data: Data?

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess {
            data = item as? Data
        }

        if data == nil {
            let fileURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/.credentials.json")
            data = try? Data(contentsOf: fileURL)
        }

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    // MARK: - Parsing

    nonisolated private static func parseWindows(_ json: [String: Any]) -> [LimitWindow] {
        var result: [LimitWindow] = []
        var seenLabels = Set<String>()

        func append(label: String, percentUsed: Double, resetsAt: Date?) {
            guard seenLabels.insert(label).inserted else { return }
            let left = max(0, min(100, 100 - Int(percentUsed.rounded())))
            result.append(LimitWindow(label: label, percentLeft: left, resetsAt: resetsAt))
        }

        // Known windows first (stable display order), then anything the API
        // adds later — unknown keys with the same shape become extra rows.
        let knownOrder = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]
        let extraKeys = json.keys
            .filter { !knownOrder.contains($0) && $0 != "limits" && $0 != "extra_usage" }
            .sorted()
        for key in knownOrder + extraKeys {
            guard let dict = json[key] as? [String: Any],
                  let utilization = (dict["utilization"] as? NSNumber)?.doubleValue else { continue }
            append(label: prettyLabel(key),
                   percentUsed: utilization,
                   resetsAt: parseDate(dict["resets_at"] as? String))
        }

        // Newer schema variant: self-describing entries in a "limits" array
        // ({kind, percent, resets_at, scope.model.display_name}).
        if let limits = json["limits"] as? [[String: Any]] {
            for entry in limits {
                guard let percent = (entry["percent"] as? NSNumber)?.doubleValue else { continue }
                var label: String
                switch entry["kind"] as? String {
                case "session": label = "Session"
                case "weekly_all": label = "Weekly"
                case let kind?: label = prettyLabel(kind)
                case nil: label = "Limit"
                }
                if let scope = entry["scope"] as? [String: Any],
                   let model = scope["model"] as? [String: Any],
                   let name = model["display_name"] as? String {
                    label = "Weekly · \(name)"
                }
                append(label: label,
                       percentUsed: percent,
                       resetsAt: parseDate(entry["resets_at"] as? String))
            }
        }

        return result
    }

    nonisolated private static func prettyLabel(_ key: String) -> String {
        switch key {
        case "five_hour": return "Session"
        case "seven_day": return "Weekly"
        default:
            if key.hasPrefix("seven_day_") {
                let model = key.dropFirst("seven_day_".count)
                    .replacingOccurrences(of: "_", with: " ").capitalized
                return "Weekly · \(model)"
            }
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    nonisolated private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: raw) { return date }
        // The API sends microsecond fractions ("...59.771647+00:00") which
        // ISO8601DateFormatter can't parse — strip the fraction and retry.
        if let dotIndex = raw.firstIndex(of: ".") {
            let tail = raw[raw.index(after: dotIndex)...]
            if let endIndex = tail.firstIndex(where: { !$0.isNumber }) {
                return plain.date(from: String(raw[..<dotIndex]) + String(raw[endIndex...]))
            }
        }
        return nil
    }
}
