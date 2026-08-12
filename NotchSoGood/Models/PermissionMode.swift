import Foundation

/// The agent's live permission mode, sent on every Claude Code hook payload as
/// `permission_mode` (it's part of the base hook schema, alongside
/// `session_id` / `transcript_path` / `cwd`).
///
/// This is the authoritative signal — a user who flipped to bypass mode with
/// shift-tab is in bypass mode regardless of what settings.json says, and
/// prompting them again from the notch is a second gate they never asked for.
enum PermissionMode: String, Codable, CaseIterable {
    /// Standard behaviour — the agent prompts for dangerous operations.
    case standard = "default"
    /// Read-only planning; the agent refuses mutations on its own.
    case plan
    /// File edits are auto-accepted, everything else still prompts.
    case acceptEdits
    /// The agent classifies each call itself and only escalates the risky ones.
    case auto
    /// All permission checks bypassed.
    case bypassPermissions

    static func from(_ raw: String?) -> PermissionMode {
        guard let raw, !raw.isEmpty, let mode = PermissionMode(rawValue: raw) else { return .standard }
        return mode
    }

    /// True when the agent is deciding for itself, so any prompt we raise is
    /// redundant — and worse, blocking, because the hook waits on our answer.
    var suppressesPrompts: Bool {
        switch self {
        case .bypassPermissions, .auto, .plan: return true
        case .standard, .acceptEdits: return false
        }
    }

    /// Tools this mode approves without asking.
    func autoApproves(toolName: String) -> Bool {
        if suppressesPrompts { return true }
        if self == .acceptEdits { return Self.editTools.contains(toolName) }
        return false
    }

    /// Tools `acceptEdits` covers — file mutations, nothing else.
    private static let editTools: Set<String> = [
        "Edit", "MultiEdit", "Write", "NotebookEdit",
    ]

    /// Short label for the session row; nil for the mode that needs no callout.
    var badgeLabel: String? {
        switch self {
        case .standard: return nil
        case .plan: return "plan"
        case .acceptEdits: return "auto-edit"
        case .auto: return "auto"
        case .bypassPermissions: return "bypass"
        }
    }

    /// Parse `permissions.defaultMode` out of a settings.json dictionary.
    /// Only a fallback — the per-event `permission_mode` wins when present.
    static func fromSettings(_ json: [String: Any]) -> PermissionMode? {
        if let perms = json["permissions"] as? [String: Any],
           let raw = perms["defaultMode"] as? String,
           let mode = PermissionMode(rawValue: raw) {
            return mode
        }
        // Legacy / CLI-flag equivalents that mean "never ask".
        if json["dangerouslySkipPermissions"] as? Bool == true { return .bypassPermissions }
        if json["skipDangerousModePermissionPrompt"] as? Bool == true { return .bypassPermissions }
        return nil
    }
}
