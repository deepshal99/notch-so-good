import Foundation

/// The first-run practice tour: five real cards in the notch, each done by
/// doing (allow one, answer one, reply to one) instead of reading about it.
/// Skippable at every step; a real agent card ends it on the spot.
@MainActor
final class Tour {
    static let shared = Tour()
    private(set) var isActive = false
    private var step = 0
    private static let total = 5
    static let sessionId = "tour"

    func start() {
        isActive = true
        step = 0
        show()
    }

    /// Leave the tour (Skip, Esc).
    func skip() {
        guard isActive else { return }
        isActive = false
        NotificationManager.shared.windowController.endTour()
    }

    /// A real card needs the notch: the practice gives way, quietly.
    func yield() {
        guard isActive else { return }
        isActive = false
        NotificationManager.shared.windowController.endTour()
    }

    /// The intro's "Show me".
    func next() { advance() }

    /// The practice approval or question was answered.
    func answered(_ response: CardResponse) {
        guard isActive else { return }
        if case .answer(let answers) = response, let pick = answers.values.first {
            let manager = NotificationManager.shared
            switch pick {
            case Self.soundAll: manager.soundEnabled = true; manager.soundOnlyWhenBlocked = false
            case Self.soundBlocked: manager.soundEnabled = true; manager.soundOnlyWhenBlocked = true
            case Self.soundNever: manager.soundEnabled = false
            default: break
            }
        }
        advance()
    }

    func replied(_ text: String) {
        guard isActive else { return }
        advance()
    }

    private func advance() {
        step += 1
        // A beat between cards, so each one arrives instead of swapping.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.isActive else { return }
            if self.step >= Self.total - 1 {
                self.isActive = false
                self.showDone()
            } else {
                self.show()
            }
        }
    }

    private static let soundAll = "Always"
    private static let soundBlocked = "Only when blocked"
    private static let soundNever = "Never"

    /// The cards, for the snapshot sheet.
    static func previewCards() -> [NotchNotification] {
        let tour = Tour()
        return (0..<4).map { tour.step = $0; return tour.card() } + [tour.doneCard()]
    }

    private func show() {
        NotificationManager.shared.windowController.showNotification(card())
    }

    private func card() -> NotchNotification {
        let name = CharacterSettings.shared.kind.displayName
        var card: NotchNotification
        switch step {
        case 0:
            card = NotchNotification(type: .general, message: "Quick practice run? 30 seconds.", title: "Hi, I'm \(name)")
            card.tour = TourStep(index: 0, total: Self.total, primary: "Show me", celebrate: "wave")
        case 1:
            card = NotchNotification(type: .permission, message: "Practice: Allow, or ⌃⌥A", title: "Run command",
                                     permissionRequestId: "tour-allow", toolName: "Bash", detail: "echo \"hi, \(name)\"",
                                     interaction: .permission(always: nil))
            card.tour = TourStep(index: 1, total: Self.total)
        case 2:
            let question = AgentQuestion(question: "When should I make a sound?", header: "Sound", multiSelect: false, options: [
                .init(label: Self.soundAll, description: "Finished, waiting, errors"),
                .init(label: Self.soundBlocked, description: "When I'm waiting on you"),
                .init(label: Self.soundNever, description: "I'll just glow"),
            ])
            card = NotchNotification(type: .permission, message: question.question, title: "Sound",
                                     permissionRequestId: "tour-ask", toolName: "AskUserQuestion",
                                     interaction: .question([question]))
            card.tour = TourStep(index: 2, total: Self.total)
        default:
            card = NotchNotification(type: .complete, message: "Practice: reply to me. Anything works.",
                                     sessionId: Self.sessionId, canReply: true)
            card.tour = TourStep(index: 3, total: Self.total)
        }
        return card
    }

    private func showDone() {
        NotificationManager.shared.windowController.showNotification(doneCard())
    }

    private func doneCard() -> NotchNotification {
        let agents = [Health.claudeConnected ? "Claude Code" : nil, Health.codexConnected ? "Codex" : nil].compactMap { $0 }
        let watching = agents.isEmpty ? "Start an agent and I'll be here." : "Watching \(agents.joined(separator: " and "))."
        var card = NotchNotification(type: .complete, message: watching, title: "You're set")
        card.tour = TourStep(index: Self.total - 1, total: Self.total, celebrate: "twirl")
        return card
    }
}
