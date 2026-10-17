import AppKit
import ApplicationServices

/// Is everything connected? Hooks, events, usage and permissions, each as one
/// line a person can read (Settings → About), plus a plain-text report to paste
/// into a bug report.
@MainActor
enum Health {
    struct Check: Identifiable {
        enum Level { case good, warning, off }
        let id: String
        let title: String
        let detail: String
        let level: Level
    }

    static func checks() -> [Check] {
        [claudeHooks(), codexHooks(), geminiHooks(), events(), usage(), accessibility()].compactMap { $0 }
    }

    static func report() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let lines = checks().map { "\($0.level == .good ? "✓" : ($0.level == .warning ? "!" : "–")) \($0.title): \($0.detail)" }
        return (["Notch So Good \(version) (\(build)), macOS \(os)"] + lines).joined(separator: "\n")
    }

    // MARK: - Checks

    static var claudeConnected: Bool { ourEvents(in: claudeDir + "/settings.json").contains("Stop") }
    static var codexConnected: Bool { !ourEvents(in: NSHomeDirectory() + "/.codex/hooks.json").isEmpty }

    static var claudeDir: String {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/.claude"
    }

    /// Claude Code is here but our hooks aren't (something rewrote its
    /// settings), or Codex is here without them.
    nonisolated static func hooksMissing() -> Bool {
        let home = NSHomeDirectory()
        let claude = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
        if FileManager.default.fileExists(atPath: claude), !ourEvents(in: claude + "/settings.json").contains("Stop") { return true }
        let codex = home + "/.codex"
        // Codex only once it has a hooks file (versions without hooks never get one).
        if FileManager.default.fileExists(atPath: codex + "/hooks.json"), ourEvents(in: codex + "/hooks.json").isEmpty { return true }
        return false
    }

    nonisolated private static func ourEvents(in file: String) -> Set<String> {
        guard let data = FileManager.default.contents(atPath: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return [] }
        var events = Set<String>()
        for (event, groups) in hooks {
            for group in groups as? [[String: Any]] ?? [] {
                for hook in group["hooks"] as? [[String: Any]] ?? []
                where (hook["command"] as? String ?? "").lowercased().contains("notchsogood") {
                    events.insert(event)
                }
            }
        }
        return events
    }

    private static func claudeHooks() -> Check {
        let events = ourEvents(in: claudeDir + "/settings.json")
        if events.isEmpty {
            return Check(id: "claude", title: "Claude Code hooks", detail: "Not installed. Reinstall in General.", level: .warning)
        }
        let approvals = events.contains("PermissionRequest")
        return Check(id: "claude", title: "Claude Code hooks",
                     detail: approvals ? "Installed" : "Installed; update Claude Code for approvals in the notch",
                     level: approvals ? .good : .warning)
    }

    private static func codexHooks() -> Check {
        let dir = NSHomeDirectory() + "/.codex"
        guard FileManager.default.fileExists(atPath: dir) else {
            return Check(id: "codex", title: "Codex hooks", detail: "Codex isn't installed", level: .off)
        }
        let events = ourEvents(in: dir + "/hooks.json")
        if events.isEmpty {
            return Check(id: "codex", title: "Codex hooks", detail: "Not installed. Reinstall in General.", level: .warning)
        }
        return Check(id: "codex", title: "Codex hooks",
                     detail: events.contains("PermissionRequest") ? "Installed" : "Installed; update Codex for approvals in the notch",
                     level: .good)
    }

    /// Only listed for people who use Gemini CLI.
    private static func geminiHooks() -> Check? {
        let file = NSHomeDirectory() + "/.gemini/settings.json"
        guard FileManager.default.fileExists(atPath: file) else { return nil }
        return ourEvents(in: file).isEmpty
            ? Check(id: "gemini", title: "Gemini CLI hooks", detail: "Needs Gemini CLI 0.26 or later", level: .off)
            : Check(id: "gemini", title: "Gemini CLI hooks", detail: "Installed (watching; approve in the terminal)", level: .good)
    }

    private static func events() -> Check {
        let server = PermissionServer.shared
        guard server.isListening else {
            return Check(id: "events", title: "Agent events", detail: "Another copy of the app is receiving them", level: .warning)
        }
        guard let last = server.lastEventAt else {
            return Check(id: "events", title: "Agent events", detail: "Listening; none yet this launch", level: .good)
        }
        return Check(id: "events", title: "Agent events", detail: "Last one \(ago(last))", level: .good)
    }

    private static func usage() -> Check {
        let limits = UsageLimitsStore.shared
        switch limits.status {
        case .ready:
            let age = limits.lastUpdated.map(ago) ?? "now"
            return Check(id: "usage", title: "Usage limits", detail: "Updated \(age)",
                         level: (limits.lastUpdated.map { Date().timeIntervalSince($0) < 30*60 } ?? false) ? .good : .warning)
        case .loading: return Check(id: "usage", title: "Usage limits", detail: "Checking…", level: .off)
        case .signedOut: return Check(id: "usage", title: "Usage limits", detail: "Needs a Claude Pro / Max or Codex sign-in", level: .off)
        case .expired: return Check(id: "usage", title: "Usage limits", detail: "Sign-in expired; open Claude Code", level: .warning)
        case .unavailable: return Check(id: "usage", title: "Usage limits", detail: "Couldn't reach the usage service", level: .warning)
        }
    }

    private static func accessibility() -> Check {
        AXIsProcessTrusted()
            ? Check(id: "ax", title: "Accessibility", detail: "Allowed: jumps to the right window", level: .good)
            : Check(id: "ax", title: "Accessibility", detail: "Off: jumps to the app, not the window", level: .warning)
    }

    private static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        return seconds < 60 ? "just now" : "\(UsageLimitsStore.duration(seconds)) ago"
    }
}
