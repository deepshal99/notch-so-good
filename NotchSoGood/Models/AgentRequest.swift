import Foundation

/// One step of an agent's checklist.
struct PlanStep: Equatable {
    var id: String
    var title: String
    /// "pending", "in_progress" or "completed" (empty: unchanged, in an update).
    var status: String

    init(id: String, title: String, status: String) {
        self.id = id; self.title = title; self.status = status
    }

    init?(json: [String: Any], index: Int) {
        guard let title = json["title"] as? String else { return nil }
        self.init(id: json["id"] as? String ?? "\(index)", title: title, status: json["status"] as? String ?? "pending")
    }
}

/// What a waiting card asks of the user, and how they can answer.
enum CardInteraction: Equatable {
    /// A tool call the agent wants to run. `always` is the rule "Always allow"
    /// would save, exactly as Claude Code suggests it ("Bash(npm test)"), with
    /// where it goes; nil when there's nothing to save (Codex, or no suggestion).
    case permission(always: AlwaysRule?)
    /// A plan waiting for approval before the agent leaves plan mode.
    case plan
    /// One to four multiple-choice questions.
    case question([AgentQuestion])

    struct AlwaysRule: Equatable {
        let label: String
        /// "localSettings", "projectSettings", "userSettings" or "session".
        let destination: String

        /// "this project" / "all projects" / "this session".
        var scope: String {
            switch destination {
            case "userSettings": return "all projects"
            case "session": return "this session"
            default: return "this project"
            }
        }
    }
}

/// An `AskUserQuestion` question, as the card shows it.
struct AgentQuestion: Equatable {
    struct Option: Equatable {
        let label: String
        let description: String
    }

    let question: String
    let header: String
    let multiSelect: Bool
    let options: [Option]

    init(question: String, header: String, multiSelect: Bool, options: [Option]) {
        self.question = question
        self.header = header
        self.multiSelect = multiSelect
        self.options = options
    }

    /// From the hook's cleaned JSON; nil if it isn't a usable question.
    init?(json: [String: Any]) {
        guard let question = json["question"] as? String, !question.isEmpty,
              let raw = json["options"] as? [[String: Any]] else { return nil }
        let options = raw.compactMap { option -> Option? in
            guard let label = option["label"] as? String, !label.isEmpty else { return nil }
            return Option(label: label, description: option["description"] as? String ?? "")
        }
        guard !options.isEmpty else { return nil }
        self.init(question: question, header: json["header"] as? String ?? "",
                  multiSelect: json["multiSelect"] as? Bool ?? false, options: Array(options.prefix(6)))
    }

    /// The answer string Claude Code expects: the label, or labels joined with
    /// commas for multi-select.
    static func answer(_ labels: [String]) -> String { labels.joined(separator: ", ") }
}

/// How the user answered a waiting card.
enum CardResponse: Equatable {
    case allow
    /// Allow, and keep allowing the same thing until the session ends.
    case allowSession
    case allowAlways
    case deny
    /// Approve a plan; `acceptEdits` also switches the session to auto-accept edits.
    case approvePlan(acceptEdits: Bool)
    /// Question text → chosen answer.
    case answer([String: String])
    /// Give the decision back to the agent's own prompt in the terminal.
    case handOff

    /// The reply the hook bridge turns into the agent's own format.
    var reply: [String: Any]? {
        switch self {
        case .allow: return ["decision": "allow"]
        case .allowSession: return ["decision": "allow", "session": true]
        case .allowAlways: return ["decision": "allow", "always": true]
        case .deny: return ["decision": "deny", "reason": "Denied from Notch So Good"]
        case .approvePlan(let acceptEdits): return ["decision": "allow", "mode": acceptEdits ? "acceptEdits" : "default"]
        case .answer(let answers): return ["answers": answers]
        case .handOff: return nil
        }
    }
}

/// A command or plan shown in full on a card: control characters out (they
/// could hide what's really there), newlines and tabs kept, length capped.
enum CardText {
    static let limit = 4000

    static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let scalars = raw.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        var text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        // Tabs read as wide gaps in a narrow well.
        text = text.replacingOccurrences(of: "\t", with: "  ")
        guard !text.isEmpty else { return nil }
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    /// A plan's opening: its first heading (as the card's subtitle) and the rest.
    static func planSummary(_ plan: String) -> (title: String?, body: String) {
        var lines = plan.components(separatedBy: "\n")
        var title: String?
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            title = lines[first].trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            lines.remove(at: first)
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == true ? nil : title, body)
    }
}
