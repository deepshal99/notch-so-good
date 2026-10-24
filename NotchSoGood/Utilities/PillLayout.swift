import Foundation

/// Row metrics for the expanded session pill.
///
/// The window controller must size its panel *before* SwiftUI lays anything out,
/// so it and `SessionPillView` both derive the drop-down height from here.
enum PillLayout {
    static let dropTopPad: CGFloat = 4
    /// How far the character may hang below the notch line (pill and cards):
    /// reaching for you, it swings lower than the strip.
    static let characterOverhang: CGFloat = 14
    static let dropBottomPad: CGFloat = 10
    static let sessionRow: CGFloat = 46
    static let groupHeader: CGFloat = 26
    /// A session under its repo's header: the same two lines, naming its workspace.
    static let subSessionRow: CGFloat = sessionRow
    static let subagentRow: CGFloat = 26
    /// "5-hour window · 62% left · resets in 2h 14m" with its bar.
    static let runwayFooter: CGFloat = 46

    /// Ceiling for the session list. Past this it scrolls rather than being
    /// silently clipped by the panel.
    static let maxListHeight: CGFloat = 300
    /// Ceiling for the whole drop-down, footer included (the panel's size).
    static let maxContentHeight: CGFloat = dropTopPad + maxListHeight + runwayFooter + dropBottomPad

    static let wingCollapsed: CGFloat = 56
    /// The pill's frame rate between events: smooth for breathing and reading
    /// (which only redraw when they visibly move); glances, tricks, reactions
    /// and hover run at 60.
    static let restingFPS = 30
    static let wingExpanded: CGFloat = 110

    /// Height the session list wants, before clamping.
    static func naturalListHeight(for sessions: [NotificationManager.SessionInfo]) -> CGFloat {
        var height: CGFloat = 0
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

    static func listHeight(for sessions: [NotificationManager.SessionInfo]) -> CGFloat {
        min(naturalListHeight(for: sessions), maxListHeight)
    }

    static func needsScrolling(_ sessions: [NotificationManager.SessionInfo]) -> Bool {
        naturalListHeight(for: sessions) > maxListHeight
    }

    static func contentHeight(for sessions: [NotificationManager.SessionInfo], runway: Bool) -> CGFloat {
        dropTopPad + listHeight(for: sessions) + (runway ? runwayFooter : 0) + dropBottomPad
    }

    static func expandedHeight(for sessions: [NotificationManager.SessionInfo], notchHeight: CGFloat, runway: Bool) -> CGFloat {
        notchHeight + contentHeight(for: sessions, runway: runway)
    }
}
