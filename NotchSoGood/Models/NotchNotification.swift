import Foundation

struct NotchNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let message: String
    let title: String?
    let sessionId: String?
    let sourceBundleId: String?
    let timestamp = Date()

    // Permission approval fields (non-nil when this is an interactive permission request)
    let permissionRequestId: String?
    let toolName: String?

    /// Ingress limits. Hook payloads and URL parameters are untrusted input:
    /// a 50 KB assistant message or a control-character-laden path would wreck
    /// the notch layout, so everything is clamped here — the one place every
    /// construction path funnels through.
    private static let messageLimit = 300
    private static let titleLimit = 80

    init(
        type: NotificationType,
        message: String,
        title: String? = nil,
        sessionId: String? = nil,
        sourceBundleId: String? = nil,
        permissionRequestId: String? = nil,
        toolName: String? = nil
    ) {
        self.type = type
        self.message = Self.clean(message, limit: Self.messageLimit) ?? type.defaultTitle
        self.title = Self.clean(title, limit: Self.titleLimit)
        self.sessionId = Self.nonEmpty(sessionId)
        self.sourceBundleId = Self.nonEmpty(sourceBundleId)
        self.permissionRequestId = Self.nonEmpty(permissionRequestId)
        self.toolName = Self.nonEmpty(toolName)
    }

    /// Collapse whitespace runs, strip control characters, clamp length.
    /// Whitespace is collapsed *before* stripping controls so "a\nb" stays
    /// "a b" rather than becoming "ab".
    static func clean(_ raw: String?, limit: Int) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let printable = collapsed.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(printable))
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit - 1)) + "…"
    }

    /// Treat empty strings as absent. Hooks send `""` for unknown fields, and an
    /// empty session id used to create untargetable sessions and no-op lookups.
    static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Titles the app itself uses for its own heads-ups; the character keys off them.
    static let limitsTitle = "Running low"
    static let nudgeTitle = "Still waiting on you"

    var displayTitle: String {
        title ?? type.defaultTitle
    }

    var isInteractivePermission: Bool {
        permissionRequestId != nil
    }
}
