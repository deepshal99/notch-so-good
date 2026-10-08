import SwiftUI

/// A session as the island shows it: its colour, what it's working on, where
/// and what it's doing right now, and how long it's been going. One component
/// for the notch's list and the menu bar panel, so the two can't drift apart.
struct IslandSessionRow: View {
    let session: NotificationManager.SessionInfo

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: session.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.taskTitle ?? session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Island.primary)
                        .lineLimit(1)
                        .truncationMode(session.taskTitle == nil ? .middle : .tail)
                    SessionRowParts.badges(for: session)
                }
                HStack(spacing: 0) {
                    if session.taskTitle != nil {
                        // The project keeps a readable share of the line; the
                        // activity truncates instead of squeezing it to nothing.
                        Text(session.projectName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 130, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        Text(" · ").fixedSize()
                    }
                    SessionRowParts.activity(session)
                }
                .font(.system(size: 11.5))
                .foregroundColor(Island.tertiary)
            }
            Spacer(minLength: 8)
            SessionRowParts.trailing(session: session)
        }
    }
}

/// The pieces a session row is made of, shared with the grouped sub-rows.
enum SessionRowParts {
    static func activity(_ session: NotificationManager.SessionInfo, emphasised: Bool = false) -> some View {
        let waiting = session.status == .needsInput || session.status == .needsPermission
        return Text(session.status.activityLine(toolName: session.activeToolName, toolDetail: session.activeToolDetail))
            .font(.system(size: emphasised ? 12.5 : 11.5, weight: emphasised ? .medium : .regular))
            .foregroundColor(waiting ? CharacterState.need.color : (emphasised ? Color.white.opacity(0.82) : Island.secondary))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    static func badges(for session: NotificationManager.SessionInfo) -> some View {
        if session.agentSource != .claude {
            Chip(text: session.agentSource.displayName, mono: false, tint: session.agentSource.accentColor, height: 17)
        }
        if let mode = session.permissionMode.badgeLabel {
            Chip(text: mode, mono: false, height: 17)
        }
    }

    static func trailing(session: NotificationManager.SessionInfo) -> some View {
        HStack(spacing: 8) {
            let running = session.subagents.filter { $0.status == .running }.count
            if running > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill").font(.system(size: 9, weight: .semibold))
                    Text("\(running)").font(Island.numeric)
                }
                .foregroundColor(Island.tertiary)
                .accessibilityLabel("\(running) subagent\(running == 1 ? "" : "s") running")
            }
            ElapsedText(since: session.startTime)
        }
    }

    static func accessibilityLabel(_ session: NotificationManager.SessionInfo) -> String {
        let phase = session.status.activityLine(toolName: session.activeToolName, toolDetail: session.activeToolDetail)
        let elapsed = ElapsedFormatter.precise(Int(Date().timeIntervalSince(session.startTime)))
        var label = "\(session.taskTitle ?? session.projectName), \(session.agentSource.displayName), \(phase), \(elapsed)"
        if let mode = session.permissionMode.badgeLabel { label += ", \(mode) mode" }
        return label
    }
}

/// A soft highlight on hover, concentric with the island's corners.
struct IslandRowStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : (hovered ? 0.06 : 0)))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Island.press, value: configuration.isPressed)
            .onHover { h in withAnimation(.hover) { hovered = h } }
    }
}

/// A running clock in a label. Only this text re-renders each tick, never the
/// view around it: the pill and menu used to rebuild whole trees every second
/// just to move a timer.
struct ElapsedText: View {
    let since: Date
    var compact = false
    var font: Font = Island.numeric
    var color: Color = Island.tertiary

    var body: some View {
        // Precise times tick every second; compact ones (1h08m) only by the minute.
        TimelineView(.periodic(from: .now, by: compact && Date().timeIntervalSince(since) >= 3600 ? 60 : 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(since))
            Text(compact ? ElapsedFormatter.compact(seconds) : ElapsedFormatter.precise(seconds))
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
