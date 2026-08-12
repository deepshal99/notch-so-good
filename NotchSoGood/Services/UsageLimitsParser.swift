import Foundation

/// Pure parsing for the rate-limit payloads, split out from `UsageLimitsStore`
/// so it can be tested against recorded responses without Keychain or network.
enum UsageLimitsParser {
    struct Window: Equatable {
        let label: String
        let percentLeft: Int   // 0–100
        let resetsAt: Date?
    }

    // MARK: - Claude Code (api.anthropic.com/api/oauth/usage)

    /// Windows we recognise, in display order.
    private static let knownKeys = ["five_hour", "seven_day"]

    /// The endpoint also returns internal codenames for unreleased features
    /// (`nimbus_quill`, `tangelo`, `amber_ladder`, …). Some carry a
    /// `utilization` of 0, so the old "append anything with a utilization"
    /// catch-all rendered them as real rows — e.g. "Nimbus Quill — 100% left".
    /// Only per-model weekly buckets are accepted beyond the known keys.
    private static func isRecognisedKey(_ key: String) -> Bool {
        if knownKeys.contains(key) { return true }
        guard key.hasPrefix("seven_day_") else { return false }
        // seven_day_opus / seven_day_sonnet are real; seven_day_omelette is not.
        let model = key.dropFirst("seven_day_".count)
        return ["opus", "sonnet", "haiku"].contains(String(model))
    }

    static func parseClaude(_ json: [String: Any]) -> [Window] {
        var result: [Window] = []
        var seenLabels = Set<String>()

        func append(label: String, percentUsed: Double, resetsAt: Date?) {
            guard seenLabels.insert(label).inserted else { return }
            let left = max(0, min(100, 100 - Int(percentUsed.rounded())))
            result.append(Window(label: label, percentLeft: left, resetsAt: resetsAt))
        }

        // Known windows first, in a stable order.
        let extraKeys = json.keys.filter { isRecognisedKey($0) && !knownKeys.contains($0) }.sorted()
        for key in knownKeys + extraKeys {
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

    static func prettyLabel(_ key: String) -> String {
        switch key {
        case "five_hour", "session": return "Session"
        case "seven_day", "weekly_all": return "Weekly"
        default:
            if key.hasPrefix("seven_day_") {
                let model = key.dropFirst("seven_day_".count)
                    .replacingOccurrences(of: "_", with: " ").capitalized
                return "Weekly · \(model)"
            }
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Codex CLI (chatgpt.com/backend-api/wham/usage)

    static func parseCodex(_ json: [String: Any]) -> [Window] {
        guard let rateLimit = json["rate_limit"] as? [String: Any] else { return [] }
        var result: [Window] = []

        func append(label: String, dict: [String: Any]?) {
            guard let dict,
                  let usedPercent = (dict["used_percent"] as? NSNumber)?.doubleValue else { return }
            let left = max(0, min(100, 100 - Int(usedPercent.rounded())))
            result.append(Window(label: label, percentLeft: left, resetsAt: codexResetDate(from: dict)))
        }

        // primary_window = rolling 5-hour window, secondary_window = rolling weekly.
        append(label: "Session", dict: rateLimit["primary_window"] as? [String: Any])
        append(label: "Weekly", dict: rateLimit["secondary_window"] as? [String: Any])
        return result
    }

    /// The endpoint reports the reset as an absolute epoch, a countdown in
    /// seconds, or an ISO8601 string depending on version.
    static func codexResetDate(from dict: [String: Any]) -> Date? {
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

    // MARK: - Dates

    static func parseDate(_ raw: String?) -> Date? {
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
