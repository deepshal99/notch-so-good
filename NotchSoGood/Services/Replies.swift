import Foundation

/// Reply from the notch: which finished sessions are listening for a reply
/// typed on their card (their Stop hook waits in the background).
@MainActor
final class Replies: ObservableObject {
    static let shared = Replies()
    @Published var listening: Set<String> = []

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
