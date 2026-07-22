import Foundation
import Security

/// Live rate-limit status for the menu bar — mirrors the iOS "Limits" widget,
/// extended to also cover OpenAI Codex CLI. For Claude Code it reads the OAuth
/// token from the login Keychain and polls the (undocumented) usage endpoint
/// that powers `/usage` in the CLI:
/// GET https://api.anthropic.com/api/oauth/usage
/// → {"five_hour":{"utilization":37.0,"resets_at":"ISO8601"},"seven_day":{...},
///    "seven_day_opus":{...}, ...} where utilization is percent used (0–100).
/// For Codex CLI it reads the OAuth token from ~/.codex/auth.json and polls
/// the (undocumented) endpoint that powers the ChatGPT web usage dashboard:
/// GET https://chatgpt.com/backend-api/wham/usage
/// → {"rate_limit":{"primary_window":{"used_percent":9,"reset_at":<epoch>,
///    "limit_window_seconds":18000},"secondary_window":{...}}} where
/// primary_window is the rolling 5-hour "Session" window and secondary_window
/// is the rolling weekly "Weekly" window.
/// Everything is best-effort: any failure quietly clears the windows.
@MainActor
final class UsageLimitsStore: ObservableObject {
    static let shared = UsageLimitsStore()

    struct LimitWindow: Identifiable {
        let label: String        // "Session", "Weekly", "Weekly · Opus", ...
        let percentLeft: Int     // 0–100
        let resetsAt: Date?
        var source: AgentSource = .claude
        var id: String { "\(source.rawValue)_\(label)" }
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
            // Runs off the main actor — first Keychain/file read may prompt once.
            // Claude and Codex are independent sources; fetch concurrently so a
            // slow or failing one never blocks the other.
            async let claudeFetch = Self.fetchWindows()
            async let codexFetch = Self.fetchCodexWindows()
            let claudeWindows = await claudeFetch
            let codexWindows = await codexFetch
            guard let self else { return }
            self.isFetching = false
            // Ordering contract: all Claude windows first, then Codex.
            let combined = (claudeWindows ?? []) + (codexWindows ?? [])
            if !combined.isEmpty {
                self.windows = combined
                self.lastUpdated = Date()
                self.checkLowSessionLimit()
            } else {
                self.windows = []
            }
        }
    }

    // MARK: - Low-limit warning

    private func checkLowSessionLimit() {
        guard let session = windows.first(where: { $0.source == .claude && $0.label == "Session" }),
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
        let days = secs / 86400
        let hours = (secs % 86400) / 3600
        let minutes = (secs % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
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
        // Read via /usr/bin/security (Apple-signed, stable identity): one
        // "Always Allow" then survives app updates. SecItemCopyMatching from
        // this ad-hoc-signed binary would re-prompt after every re-sign.
        var data: Data?

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        if (try? task.run()) != nil {
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let out = pipe.fileHandleForReading.readDataToEndOfFile()
                if let raw = String(data: out, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !raw.isEmpty {
                    data = raw.data(using: .utf8)
                }
            }
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

    // MARK: - Codex (off main actor)

    /// Mirrors `fetchWindows()` above but for OpenAI Codex CLI. Reads the
    /// OAuth token Codex CLI stores at ~/.codex/auth.json and polls the
    /// (undocumented) endpoint that backs the ChatGPT web usage dashboard.
    /// Any failure — missing file, missing token, network error, or an
    /// unexpected response shape — is silent and returns nil; it never crashes.
    nonisolated private static func fetchCodexWindows() async -> [LimitWindow]? {
        guard let credentials = loadCodexCredentials(),
              let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NotchSoGood/1.0", forHTTPHeaderField: "User-Agent")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return parseCodexWindows(json)
        } catch {
            return nil
        }
    }

    /// Codex CLI stores OAuth creds as JSON at ~/.codex/auth.json:
    /// {"tokens":{"access_token":...,"account_id":...}, ...} (some builds use
    /// camelCase keys instead — both are accepted defensively).
    nonisolated private static func loadCodexCredentials() -> (accessToken: String, accountId: String?)? {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = (tokens["access_token"] as? String) ?? (tokens["accessToken"] as? String),
              !accessToken.isEmpty else { return nil }
        let accountId = (tokens["account_id"] as? String) ?? (tokens["accountId"] as? String)
        return (accessToken, accountId)
    }

    nonisolated private static func parseCodexWindows(_ json: [String: Any]) -> [LimitWindow] {
        guard let rateLimit = json["rate_limit"] as? [String: Any] else { return [] }
        var result: [LimitWindow] = []

        func append(label: String, dict: [String: Any]?) {
            guard let dict,
                  let usedPercent = (dict["used_percent"] as? NSNumber)?.doubleValue else { return }
            let left = max(0, min(100, 100 - Int(usedPercent.rounded())))
            result.append(LimitWindow(
                label: label,
                percentLeft: left,
                resetsAt: codexResetDate(from: dict),
                source: .codex))
        }

        // primary_window = rolling 5-hour window, secondary_window = rolling weekly window.
        append(label: "Session", dict: rateLimit["primary_window"] as? [String: Any])
        append(label: "Weekly", dict: rateLimit["secondary_window"] as? [String: Any])

        return result
    }

    /// The endpoint has been observed to report the reset either as an
    /// absolute epoch timestamp ("reset_at" / "resets_at") or as a countdown
    /// in seconds ("resets_in_seconds"); an ISO8601 string is accepted too.
    nonisolated private static func codexResetDate(from dict: [String: Any]) -> Date? {
        if let seconds = (dict["resets_in_seconds"] as? NSNumber)?.doubleValue {
            return Date().addingTimeInterval(seconds)
        }
        if let epoch = (dict["reset_at"] as? NSNumber)?.doubleValue {
            return Date(timeIntervalSince1970: epoch)
        }
        if let epoch = (dict["resets_at"] as? NSNumber)?.doubleValue {
            return Date(timeIntervalSince1970: epoch)
        }
        if let raw = (dict["reset_at"] as? String) ?? (dict["resets_at"] as? String) {
            return parseDate(raw)
        }
        return nil
    }
}
