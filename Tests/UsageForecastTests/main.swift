import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let fiveHours: TimeInterval = 5 * 3600

// Two hours in, 60% used: 30%/h, 40% left lasts 80 min — before the 3 h reset.
let hot = UsageForecast.outcome(percentLeft: 40, resetsAt: now.addingTimeInterval(3 * 3600), windowLength: fiveHours, now: now)
if case .runsOut(let date)? = hot {
    check(abs(date.timeIntervalSince(now) - 80 * 60) < 1, "fast burn runs out in 80 minutes")
} else { check(false, "fast burn runs out in 80 minutes") }

// Two hours in, 20% used: 10%/h, 80% left lasts 8 h — past the reset.
check(UsageForecast.outcome(percentLeft: 80, resetsAt: now.addingTimeInterval(3 * 3600), windowLength: fiveHours, now: now) == .lastsUntilReset,
      "slow burn lasts until the reset")

// Five minutes in: too early to say.
check(UsageForecast.outcome(percentLeft: 90, resetsAt: now.addingTimeInterval(fiveHours - 300), windowLength: fiveHours, now: now) == nil,
      "no forecast in the first ten minutes")

// Barely used: no forecast.
check(UsageForecast.outcome(percentLeft: 99, resetsAt: now.addingTimeInterval(3600), windowLength: fiveHours, now: now) == nil,
      "no forecast under 2% used")

// Already empty.
check(UsageForecast.outcome(percentLeft: 0, resetsAt: now.addingTimeInterval(3600), windowLength: fiveHours, now: now) == .runsOut(now),
      "empty window has run out")

// Reset already passed (stale data).
check(UsageForecast.outcome(percentLeft: 50, resetsAt: now.addingTimeInterval(-60), windowLength: fiveHours, now: now) == nil,
      "no forecast once the window has reset")

check(UsageForecast.headsUpLevel(percentLeft: 25) == nil, "no heads-up at 75% used")
check(UsageForecast.headsUpLevel(percentLeft: 20) == 80, "heads-up at 80% used")
check(UsageForecast.headsUpLevel(percentLeft: 6) == 80, "still the 80% level at 94% used")
check(UsageForecast.headsUpLevel(percentLeft: 5) == 95, "heads-up at 95% used")
check(UsageForecast.headsUpLevel(percentLeft: 0) == 95, "empty is the 95% level")
check(UsageForecast.windowLength(label: "Session") == fiveHours, "Session is five hours")
check(UsageForecast.windowLength(label: "Weekly · Opus") == 7 * 86400, "Weekly windows are seven days")
check(UsageForecast.windowLength(label: "Other") == nil, "unknown windows have no length")

print(failures == 0 ? "All forecast checks passed." : "\(failures) forecast check(s) failed.")
exit(failures == 0 ? 0 : 1)
