import SwiftUI

enum SessionStatus: String {
    case running
    case needsInput
    case needsPermission
    case compacting
    case completed

    var dotColor: Color {
        switch self {
        case .running:         return Color(hex: "4ADE80") // green
        case .needsInput:      return Color(hex: "60A5FA") // blue
        case .needsPermission: return Color(hex: "FBBF24") // amber
        case .compacting:      return Color(hex: "A78BFA") // violet
        case .completed:       return Color(hex: "4ADE80").opacity(0.5)
        }
    }

    var shouldPulse: Bool {
        switch self {
        case .running, .compacting: return true
        case .needsInput, .needsPermission: return true
        case .completed: return false
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

    // MARK: - Phase icon (SF Symbol)

    var phaseIcon: String {
        switch self {
        case .running:         return "bolt.fill"
        case .needsInput:      return "bubble.left.fill"
        case .needsPermission: return "lock.shield.fill"
        case .compacting:      return "arrow.triangle.2.circlepath"
        case .completed:       return "checkmark.circle.fill"
        }
    }

    /// Icon for a specific tool name (overrides the generic phase icon)
    static func toolIcon(_ toolName: String) -> String {
        switch toolName {
        case "Read", "Glob", "Grep":      return "doc.text.magnifyingglass"
        case "Bash":                       return "terminal.fill"
        case "Edit":                       return "pencil.line"
        case "Write":                      return "doc.badge.plus"
        case "Agent":                      return "person.2.fill"
        case "WebSearch", "WebFetch":      return "globe"
        case "Skill":                      return "star.fill"
        case "NotebookEdit":              return "doc.text.fill"
        default:
            if toolName.hasPrefix("mcp__") { return "puzzlepiece.fill" }
            return "bolt.fill"
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
