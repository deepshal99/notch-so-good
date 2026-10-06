import Foundation

/// What a session is working on, taken from the user's prompts. A new prompt
/// only replaces the title when it reads like a task: "yes", "continue" or
/// "lgtm" keep the previous one.
enum TaskTitle {
    private static let fillers: Set<String> = [
        "yes", "y", "yep", "yeah", "no", "n", "ok", "okay", "k", "sure", "go", "go ahead", "continue",
        "proceed", "do it", "lgtm", "thanks", "thank you", "ty", "next", "retry", "try again", "keep going",
    ]

    static func update(current: String?, prompt: String?) -> String? {
        guard let raw = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return current }
        // Slash commands and pasted output aren't task descriptions.
        if raw.hasPrefix("/") || raw.hasPrefix("{") || raw.hasPrefix("<") { return current }
        let normalized = raw.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        if fillers.contains(normalized) { return current }
        let words = raw.split(whereSeparator: \.isWhitespace).count
        guard words >= 3 || raw.count >= 18 else { return current }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
