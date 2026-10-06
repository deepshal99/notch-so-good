import Foundation

/// Commands worth a second look before allowing: they delete, overwrite or
/// rewrite history. It's a hint, not a guarantee — the card always shows the
/// full command, and the tag only adds emphasis.
enum CommandRisk {
    /// Matched case-insensitively.
    private static let patterns = [
        #"\bgit\s+push\b.*(--force|\s-f\b)"#,
        #"\bgit\s+reset\s+--hard\b"#,
        #"\bgit\s+clean\s+-[a-z]*f"#,
        #"\bdrop\s+(table|database)\b"#,
        #"\btruncate\s+table\b"#,
        #"\bmkfs\b"#,
        #"\bdd\s+if="#,
        #"\bchmod\s+-r\s+777\b"#,
        #"\bsudo\s+rm\b"#,
    ]

    /// `git branch -D` force-deletes; `-d` refuses unmerged work, so case matters.
    private static let forceBranchDelete = #"\bgit\s+branch\s+(?:\S+\s+)*(?:-[a-zA-Z]*D\b|--delete\s+--force\b|--force\s+--delete\b)"#

    /// `rm` followed by its flags, wherever it starts a command.
    private static let rmWithFlags = try! NSRegularExpression(
        pattern: #"(?:^|[\s;&|(`])rm((?:\s+-{1,2}[A-Za-z][A-Za-z-]*)+)"#
    )

    static func looksDestructive(_ command: String) -> Bool {
        if isRecursiveRemove(command) { return true }
        if command.range(of: forceBranchDelete, options: .regularExpression) != nil { return true }
        let c = command.lowercased()
        return patterns.contains { c.range(of: $0, options: .regularExpression) != nil }
    }

    /// Any `rm` that recurses: `-r`, `-R`, `-rf`, `-rfv`, `-f -r`, `-v -rf`, `--recursive`.
    private static func isRecursiveRemove(_ command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        for match in rmWithFlags.matches(in: command, range: range) {
            guard let flagsRange = Range(match.range(at: 1), in: command) else { continue }
            for token in command[flagsRange].split(whereSeparator: \.isWhitespace) {
                if token == "--recursive" { return true }
                if token.hasPrefix("-"), !token.hasPrefix("--"), token.dropFirst().contains(where: { $0 == "r" || $0 == "R" }) {
                    return true
                }
            }
        }
        return false
    }
}
