import Foundation

// Parses the recorded api.anthropic.com/api/oauth/usage response in
// Tests/Fixtures/oauth-usage.json — the real shape as of Claude Code 2.1.220,
// including the internal codenamed keys that used to leak into the menu.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print("\(ok ? "PASS" : "FAIL") \(what)")
    if !ok { failures += 1 }
}

let fixture = URL(fileURLWithPath: "Tests/Fixtures/oauth-usage.json")
guard let data = try? Data(contentsOf: fixture),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    print("FAIL could not load \(fixture.path)")
    exit(1)
}

let windows = UsageLimitsParser.parseClaude(json)
let labels = windows.map(\.label)
print("parsed: \(windows.map { "\($0.label) \($0.percentLeft)%" }.joined(separator: ", "))")

expect(labels == ["Session", "Weekly"], "only real windows are shown, in order — got \(labels)")

// The bug this guards: internal codenames arriving as usable-looking windows.
for junk in ["Nimbus Quill", "Tangelo", "Amber Ladder", "Cinder Cove",
             "Iguana Necktie", "Omelette Promotional", "Weekly · Omelette",
             "Weekly · Cowork", "Weekly · Oauth Apps"] {
    expect(!labels.contains(junk), "\(junk) is not rendered as a limit")
}

expect(windows.first?.percentLeft == 38, "Session 62% used -> 38% left (got \(windows.first?.percentLeft ?? -1))")
expect(windows.last?.percentLeft == 83, "Weekly 17% used -> 83% left (got \(windows.last?.percentLeft ?? -1))")
expect(windows.allSatisfy { $0.resetsAt != nil }, "every window has a reset date parsed")

// Microsecond fractional seconds — ISO8601DateFormatter can't do these natively.
expect(UsageLimitsParser.parseDate("2026-08-11T21:40:00.602169+00:00") != nil,
       "microsecond-precision timestamp parses")
expect(UsageLimitsParser.parseDate("2026-08-11T21:40:00Z") != nil, "plain ISO8601 parses")
expect(UsageLimitsParser.parseDate("not a date") == nil, "garbage date is nil")
expect(UsageLimitsParser.parseDate(nil) == nil, "nil date is nil")

// Per-model weekly buckets are legitimate and must survive the filter.
let withOpus: [String: Any] = [
    "five_hour": ["utilization": 10.0, "resets_at": "2026-08-11T21:40:00Z"],
    "seven_day_opus": ["utilization": 50.0, "resets_at": "2026-08-17T14:00:00Z"],
    "seven_day_omelette": ["utilization": 0.0, "resets_at": NSNull()],
]
let modelLabels = UsageLimitsParser.parseClaude(withOpus).map(\.label)
expect(modelLabels.contains("Weekly · Opus"), "per-model weekly window is kept — got \(modelLabels)")
expect(!modelLabels.contains("Weekly · Omelette"), "codenamed weekly bucket is dropped")

// Empty / malformed payloads must yield nothing rather than crash.
expect(UsageLimitsParser.parseClaude([:]).isEmpty, "empty payload -> no windows")
expect(UsageLimitsParser.parseClaude(["five_hour": "nonsense"]).isEmpty, "malformed entry -> no windows")

// Clamping.
let over = UsageLimitsParser.parseClaude(["five_hour": ["utilization": 140.0]])
expect(over.first?.percentLeft == 0, "utilization > 100 clamps to 0% left")
let under = UsageLimitsParser.parseClaude(["five_hour": ["utilization": -20.0]])
expect(under.first?.percentLeft == 100, "negative utilization clamps to 100% left")

// Codex payload shape.
let codex: [String: Any] = ["rate_limit": [
    "primary_window": ["used_percent": 9, "reset_at": 1_800_000_000],
    "secondary_window": ["used_percent": 44, "resets_in_seconds": 3600],
]]
let codexWindows = UsageLimitsParser.parseCodex(codex)
expect(codexWindows.map(\.label) == ["Session", "Weekly"], "codex windows parse in order")
expect(codexWindows.first?.percentLeft == 91, "codex 9% used -> 91% left")
expect(codexWindows.last?.resetsAt != nil, "codex countdown-style reset resolves to a date")
expect(UsageLimitsParser.parseCodex([:]).isEmpty, "codex empty payload -> no windows")

print(failures == 0 ? "\nAll usage-limit cases passed" : "\n\(failures) failures")
exit(failures == 0 ? 0 : 1)
