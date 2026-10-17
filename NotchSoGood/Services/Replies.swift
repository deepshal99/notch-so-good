import Foundation

/// Reply from the notch: which finished sessions are listening for a reply
/// typed on their card (their Stop hook waits in the background), and whether
/// this Mac's Claude Code hooks can do that at all.
@MainActor
final class Replies: ObservableObject {
    static let shared = Replies()
    @Published var listening: Set<String> = []

    /// True when the installed hooks include the reply listener (Claude Code
    /// 2.1.287+). Read from settings, refreshed after every hook install.
    private(set) var supported = false

    func refreshSupport() {
        // The installers write where $HOME points (NSHomeDirectory ignores it).
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let dir = env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
        guard let data = FileManager.default.contents(atPath: dir + "/settings.json"),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] else {
            supported = false
            return
        }
        supported = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.contains { hook in
            let command = hook["command"] as? String ?? ""
            return command.contains("notchsogood") && command.hasSuffix(" Reply") && hook["asyncRewake"] as? Bool == true
        }
    }

    /// Send a reply. The listener starts alongside the "finished" event, so
    /// give it a moment to arrive before giving up.
    func send(_ text: String, to sessionId: String, attempt: Int = 0, done: @escaping (Bool) -> Void) {
        if PermissionServer.shared.sendReply(sessionId: sessionId, text: text) { done(true); return }
        guard attempt < 10 else { done(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.send(text, to: sessionId, attempt: attempt + 1, done: done)
        }
    }
}
