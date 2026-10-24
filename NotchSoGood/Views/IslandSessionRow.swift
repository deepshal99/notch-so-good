import SwiftUI

/// A session as the island shows it: its agent, what it's working on, where
/// and what it's doing right now, and how long it's been going. One component
/// for the notch's list and the menu bar panel, so the two can't drift apart.
struct IslandSessionRow: View {
    let session: NotificationManager.SessionInfo
    /// The repo it's listed under, when grouped: the header names the repo,
    /// so the row names only its own workspace (and nothing on the main checkout).
    var group: String? = nil

    private var place: String? {
        guard let group else { return session.projectName }
        let leaf = session.projectName.components(separatedBy: " / ").last ?? session.projectName
        return leaf == group ? nil : leaf
    }

    var body: some View {
        HStack(spacing: 8) {
            // In the 14 pt column the status dot had, so the text stays put.
            AgentMark(agent: session.agentSource, working: session.status == .running)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.taskTitle ?? place ?? session.projectName)
                        .font(Island.heading)
                        .foregroundColor(Island.primary)
                        .lineLimit(1)
                        .truncationMode(session.taskTitle == nil ? .middle : .tail)
                    SessionRowParts.badges(for: session)
                }
                HStack(spacing: 0) {
                    if session.taskTitle != nil, let place {
                        // The project keeps a readable share of the line; the
                        // activity truncates instead of squeezing it to nothing.
                        Text(place)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 130, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        Text(" · ").fixedSize()
                    }
                    SessionRowParts.activity(session)
                }
                .font(Island.detail)
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
        // A plan under way says where it's up to; otherwise, the tool at hand.
        let line = (!waiting ? session.planLine : nil)
            ?? session.status.activityLine(toolName: session.activeToolName, toolDetail: session.activeToolDetail)
        return Text(line)
            .font(emphasised ? Island.body.weight(.medium) : Island.detail)
            .foregroundColor(waiting ? CharacterState.need.color : (emphasised ? Color.white.opacity(0.82) : Island.secondary))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    static func badges(for session: NotificationManager.SessionInfo) -> some View {
        if let mode = session.permissionMode.badgeLabel {
            Chip(text: mode, mono: false, height: 17)
        }
    }

    static func trailing(session: NotificationManager.SessionInfo) -> some View {
        HStack(spacing: 8) {
            let running = session.subagents.filter { $0.status == .running }.count
            if running > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill").font(Island.glyph)
                    Text("\(running)").font(Island.numeric)
                }
                .foregroundColor(Island.tertiary)
                .accessibilityLabel("\(running) subagent\(running == 1 ? "" : "s") running")
            }
            if let percent = session.contextPercent, percent >= 50 {
                ContextRing(percent: percent)
            }
            if let progress = session.planProgress {
                HStack(spacing: 3) {
                    Image(systemName: "checklist").font(Island.glyph).foregroundStyle(Island.tertiary)
                    Text("\(progress.done)/\(progress.total)").font(Island.numeric)
                }
                .foregroundColor(Island.tertiary)
                .accessibilityLabel("\(progress.done) of \(progress.total) steps done")
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

/// How full a session's context is: a small bar that fills up (not a ring,
/// so it never reads as the usage ring beside it), only once it's past half,
/// amber from 75%, red from 90%.
struct ContextRing: View {
    let percent: Int

    var body: some View {
        let color = percent >= 90 ? CharacterState.error.color : (percent >= 75 ? CharacterState.warn.color : Island.tertiary)
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color).frame(width: max(3, 14 * CGFloat(percent) / 100))
            }
            .frame(width: 14, height: 5)
            Text("\(percent)%").font(Island.numeric).foregroundColor(percent >= 75 ? color : Island.tertiary)
        }
        .help("Context \(percent)% full")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context \(percent)% full")
    }
}
