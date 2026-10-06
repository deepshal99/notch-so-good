import Foundation

/// "At this pace, runs out around 3:40 PM." Projects the average burn rate
/// since a usage window opened to when it would hit zero. The window's start
/// is implied by its reset time and length, so a forecast is available from
/// the very first reading — no sampling history needed.
enum UsageForecast {
    enum Outcome: Equatable {
        case lastsUntilReset
        case runsOut(Date)
    }

    /// How long each window runs, by the label the parser gives it.
    static func windowLength(label: String) -> TimeInterval? {
        if label == "Session" { return 5 * 3600 }
        if label.hasPrefix("Weekly") { return 7 * 86400 }
        return nil
    }

    /// Nil when there's too little signal: in the first ten minutes of a
    /// window, or before 2% has been used, a projection is noise.
    static func outcome(percentLeft: Int, resetsAt: Date, windowLength: TimeInterval, now: Date = Date()) -> Outcome? {
        let start = resetsAt.addingTimeInterval(-windowLength)
        let elapsed = now.timeIntervalSince(start)
        let left = Double(min(100, max(0, percentLeft)))
        let used = 100 - left
        guard resetsAt > now, elapsed >= 10 * 60, used >= 2 else { return nil }
        if left == 0 { return .runsOut(now) }
        let ratePerSecond = used / elapsed
        let runout = now.addingTimeInterval(left / ratePerSecond)
        return runout >= resetsAt ? .lastsUntilReset : .runsOut(runout)
    }
}
