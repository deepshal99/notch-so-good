import Foundation

/// Scores how well a window title (or terminal pane path) identifies a session's
/// working directory.
///
/// Terminals and IDEs abbreviate titles in wildly different ways — `~/dev/app`,
/// `app — zsh`, `app (main) — Cursor`, a bare leaf name — so a single
/// `contains(fullPath)` check misses most of them and the session's window never
/// gets raised. Full path, tilde form, two-segment tail, and leaf are all tried,
/// most-specific first.
enum WindowMatcher {
    static func score(candidate: String, cwd: String, homeDirectory: String = NSHomeDirectory()) -> Int {
        let haystack = candidate.lowercased()
        let full = cwd.lowercased()
        guard !haystack.isEmpty, !full.isEmpty else { return 0 }

        if haystack == full || haystack.hasSuffix(full) { return 100 }
        if haystack.contains(full) { return 90 }

        // "~/dev/app" style abbreviation of the home directory
        let home = homeDirectory.lowercased()
        if full.hasPrefix(home) {
            let tilde = "~" + full.dropFirst(home.count)
            if haystack.contains(tilde) { return 85 }
        }

        let segments = full.split(separator: "/").map(String.init)
        if segments.count >= 2 {
            let tail = segments.suffix(2).joined(separator: "/")
            if haystack.contains(tail) { return 70 }
        }
        if let leaf = segments.last, !leaf.isEmpty, haystack.contains(leaf) {
            return 50
        }
        return 0
    }
}
