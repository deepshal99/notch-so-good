import Foundation

/// The branch a working directory has checked out, read straight from
/// `.git/HEAD` — no subprocess, so it's cheap enough to call while a card
/// lays out. Follows the `gitdir:` pointer that worktrees and submodules use.
enum GitBranch {
    static func current(in cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        for _ in 0..<16 {
            let dotGit = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                var gitDir = dotGit
                if !isDirectory.boolValue {
                    guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
                          pointer.hasPrefix("gitdir:") else { return nil }
                    let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    gitDir = URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
                let ref = head.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "ref: refs/heads/"
                // A detached HEAD has no branch worth showing.
                guard ref.hasPrefix(prefix) else { return nil }
                let branch = String(ref.dropFirst(prefix.count))
                return branch.isEmpty ? nil : branch
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { return nil }
            dir = parent
        }
        return nil
    }
}
