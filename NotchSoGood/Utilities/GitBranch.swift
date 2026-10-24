import Foundation

/// The branch a working directory has checked out, read straight from
/// `.git/HEAD` — no subprocess, so it's cheap enough to call while a card
/// lays out. Follows the `gitdir:` pointer that worktrees and submodules use.
enum GitBranch {
    /// The repository a working directory belongs to, by its folder name.
    /// Worktrees (Conductor's workspaces among them) name the repository they
    /// were made from, not their own folder, so they group together.
    static func repoName(in cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        for _ in 0..<16 {
            let dotGit = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return dir.lastPathComponent }
                guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
                      pointer.hasPrefix("gitdir:") else { return dir.lastPathComponent }
                let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                let gitDir = URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL
                // A worktree's git dir says where the shared one is ("../..").
                guard let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) else {
                    return dir.lastPathComponent
                }
                let shared = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: gitDir)
                    .standardizedFileURL
                return shared.lastPathComponent == ".git" ? shared.deletingLastPathComponent().lastPathComponent : dir.lastPathComponent
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { return nil }
            dir = parent
        }
        return nil
    }

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
