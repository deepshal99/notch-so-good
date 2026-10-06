import SwiftUI

enum SessionStatus: String {
    case running
    case needsInput
    case needsPermission
    case compacting
    case completed

    /// The same colour language as the character: blue works, violet thinks,
    /// orange needs you, green is done.
    var dotColor: Color {
        switch self {
        case .running:         return Color(hex: "6FB6FF")
        case .needsInput:      return Color(hex: "FFA54D")
        case .needsPermission: return Color(hex: "FFA54D")
        case .compacting:      return Color(hex: "B79CFF")
        case .completed:       return Color(hex: "5BE49B")
        }
    }

    /// One line for the session list: "Running · npm test", "Editing · store.ts",
    /// "Thinking", "Needs approval".
    func activityLine(toolName: String?, toolDetail: String?) -> String {
        guard self == .running else { return phaseLabel() }
        guard let tool = toolName else { return "Thinking" }
        let verb: String
        switch tool {
        case "Read", "Glob", "Grep": verb = "Reading"
        case "Bash":                 verb = "Running"
        case "Edit", "MultiEdit":    verb = "Editing"
        case "Write":                verb = "Writing"
        case "Agent", "Task":        verb = "Delegating"
        case "WebSearch":            verb = "Searching"
        case "WebFetch":             verb = "Fetching"
        default:                     verb = Self.mcpServer(tool).map { "Using \($0)" } ?? "Working"
        }
        guard var detail = toolDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else { return verb }
        // File tools carry a path: the file name is the part worth reading.
        if ["Read", "Edit", "MultiEdit", "Write", "NotebookEdit"].contains(tool) {
            detail = (detail as NSString).lastPathComponent
        }
        detail = detail.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "\(verb) · \(detail)"
    }

    /// How loudly this state wants the user. The collapsed pill has room for
    /// exactly one status, so with several sessions running it must show the
    /// one that's blocked on the user — not whichever happened to start first.
    /// "mcp__my_server__create_issue" → "my_server".
    static func mcpServer(_ toolName: String) -> String? {
        let parts = toolName.components(separatedBy: "__")
        guard parts.count >= 2, parts[0] == "mcp", !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    var attentionPriority: Int {
        switch self {
        case .needsPermission: return 4
        case .needsInput:      return 3
        case .compacting:      return 2
        case .running:         return 1
        case .completed:       return 0
        }
    }

    var label: String? {
        switch self {
        case .running: return nil
        case .needsInput: return "Needs input"
        case .needsPermission: return "Permission"
        case .compacting: return "Compacting"
        case .completed: return "Done"
        }
    }

    /// Human-readable phase description
    func phaseLabel(toolName: String? = nil, toolDetail: String? = nil) -> String {
        switch self {
        case .running:
            guard let tool = toolName else { return "Working" }
            switch tool {
            case "Read", "Glob", "Grep": return "Reading"
            case "Bash":                 return toolDetail.map { shortToolLabel($0) } ?? "Running"
            case "Edit":                 return "Editing"
            case "Write":                return "Writing"
            case "Agent":                return "Delegating"
            case "WebSearch":            return "Searching"
            case "WebFetch":             return "Fetching"
            default:                     return "Working"
            }
        case .needsInput:      return "Waiting for you"
        case .needsPermission: return "Needs approval"
        case .compacting:      return "Compacting"
        case .completed:       return "Done"
        }
    }
}

private func shortToolLabel(_ detail: String) -> String {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? "command"
    return firstWord
}
