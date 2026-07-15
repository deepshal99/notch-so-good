import SwiftUI

/// Identifies which AI coding agent a session belongs to.
enum AgentSource: String, Codable, CaseIterable {
    case claude = "claude"
    case codex = "codex"
    case gemini = "gemini"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .unknown: return "Agent"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: return .orange
        case .codex: return Color(red: 0.063, green: 0.639, blue: 0.498) // #10A37F OpenAI green
        case .gemini: return Color(red: 0.278, green: 0.588, blue: 0.890) // #4796E3 Gemini blue
        case .unknown: return .gray
        }
    }

    /// Detect agent source from event metadata
    static func detect(sourceApp: String?, model: String?) -> AgentSource {
        if let app = sourceApp?.lowercased() {
            if app == "codex" || app.contains("codex") { return .codex }
            if app.contains("gemini") { return .gemini }
            if app.contains("claude") || app.contains("anthropic") { return .claude }
        }
        if let m = model?.lowercased() {
            if m.contains("gemini") { return .gemini }
            if m.contains("gpt") || m.contains("codex") || m.contains("o3") || m.contains("o4") { return .codex }
            if m.contains("claude") || m.contains("sonnet") || m.contains("opus") || m.contains("haiku") { return .claude }
        }
        // Default to claude for backward compat (existing hooks don't send source_app)
        return .claude
    }
}
