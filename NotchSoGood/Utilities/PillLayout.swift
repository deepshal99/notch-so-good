import Foundation

/// Row metrics for the expanded session pill.
///
/// The window controller must size its panel *before* SwiftUI lays anything out,
/// so it and `SessionPillView` both derive the drop-down height from here. They
/// used to carry separate copies of the same arithmetic, which is exactly the
/// kind of duplication that drifts the first time a row gains a badge.
enum PillLayout {
    static let dropTopPad: CGFloat = 4
    static let dropBottomPad: CGFloat = 10
    static let sessionRow: CGFloat = 36
    static let groupHeader: CGFloat = 22
    static let subSessionRow: CGFloat = 32
    static let subagentRow: CGFloat = 24

    /// Ceiling for the drop-down. Past this the list scrolls rather than being
    /// silently clipped by the panel, which is what happened with 7+ sessions.
    static let maxContentHeight: CGFloat = 300

    static let wingCollapsed: CGFloat = 56
    static let wingExpanded: CGFloat = 110

    /// Height the session list wants, before clamping.
    static func naturalContentHeight(for sessions: [NotificationManager.SessionInfo]) -> CGFloat {
        var height = dropTopPad + dropBottomPad
        for group in SessionGroup.from(sessions) {
            if group.sessions.count == 1 {
                height += sessionRow
                height += subagentRow * CGFloat(group.sessions[0].subagents.count)
            } else {
                height += groupHeader
                for session in group.sessions {
                    height += subSessionRow
                    height += subagentRow * CGFloat(session.subagents.count)
                }
            }
        }
        return height
    }

    static func contentHeight(for sessions: [NotificationManager.SessionInfo]) -> CGFloat {
        min(naturalContentHeight(for: sessions), maxContentHeight)
    }

    static func needsScrolling(_ sessions: [NotificationManager.SessionInfo]) -> Bool {
        naturalContentHeight(for: sessions) > maxContentHeight
    }

    static func expandedHeight(for sessions: [NotificationManager.SessionInfo], notchHeight: CGFloat) -> CGFloat {
        notchHeight + contentHeight(for: sessions)
    }
}
