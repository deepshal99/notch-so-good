import Foundation

/// "Chawd's shift report" — lightweight per-day usage counters, persisted to
/// UserDefaults as a JSON dict keyed by "yyyy-MM-dd". Keeps a rolling 14-day
/// window so the menu bar can show a glanceable daily summary without ever
/// touching message contents or paths.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    struct DayStats: Codable, Equatable {
        var sessionsStarted: Int = 0
        var tasksCompleted: Int = 0
        var permissionsApproved: Int = 0
        var permissionsDenied: Int = 0
        var activeSeconds: Int = 0
    }

    /// All retained days, keyed by "yyyy-MM-dd". Published so menu bar UI updates live.
    @Published private(set) var dailyStats: [String: DayStats] = [:]

    private static let defaultsKey = "dailyStats"
    private static let retentionDays = 14

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        load()
    }

    /// Today's counters (zeroed if nothing recorded yet).
    var today: DayStats {
        dailyStats[Self.todayKey()] ?? DayStats()
    }

    private static func todayKey() -> String {
        dayFormatter.string(from: Date())
    }

    // MARK: - Increments

    func recordSessionStarted() {
        mutateToday { $0.sessionsStarted += 1 }
    }

    func recordTaskCompleted() {
        mutateToday { $0.tasksCompleted += 1 }
    }

    func recordPermissionApproved() {
        mutateToday { $0.permissionsApproved += 1 }
    }

    func recordPermissionDenied() {
        mutateToday { $0.permissionsDenied += 1 }
    }

    func recordActiveSeconds(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        mutateToday { $0.activeSeconds += Int(seconds) }
    }

    private func mutateToday(_ change: (inout DayStats) -> Void) {
        let key = Self.todayKey()
        var stats = dailyStats[key] ?? DayStats()
        change(&stats)
        dailyStats[key] = stats
        prune()
        save()
    }

    // MARK: - Formatting helpers

    /// "3h 24m" / "45m" style compact duration for the menu bar card.
    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Persistence

    private func prune() {
        guard dailyStats.count > Self.retentionDays else { return }
        let sortedKeys = dailyStats.keys.sorted()
        let excess = sortedKeys.count - Self.retentionDays
        for key in sortedKeys.prefix(excess) {
            dailyStats.removeValue(forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) else { return }
        dailyStats = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(dailyStats) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
