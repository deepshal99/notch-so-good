import SwiftUI

/// A Dynamic Island pill that extends the notch left and right while an agent
/// is active: the character on the left, the 5-hour runway on the right. On
/// hover it opens into the session list.
struct SessionPillView: View {
    @ObservedObject var dataSource: PillDataSource
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// False on displays with no notch: there's no bezel to merge with, so the
    /// pill becomes a free-floating rounded capsule under the menu bar.
    var hasNotch: Bool = true
    let onTap: (String?) -> Void
    @ObservedObject var hoverMonitor: PillHoverMonitor

    @State private var appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped whenever a session changes, so the character knows something happened.
    @State private var activity = 0
    @ObservedObject private var limits = UsageLimitsStore.shared

    init(dataSource: PillDataSource, notchWidth: CGFloat, notchHeight: CGFloat, hasNotch: Bool = true,
         onTap: @escaping (String?) -> Void, hoverMonitor: PillHoverMonitor, appearImmediately: Bool = false) {
        self.dataSource = dataSource
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hasNotch = hasNotch
        self.onTap = onTap
        self.hoverMonitor = hoverMonitor
        _appeared = State(initialValue: appearImmediately)
    }
    private var hovered: Bool { hoverMonitor.isHovered }

    private var sessions: [NotificationManager.SessionInfo] { dataSource.sessions }
    private var primaryStartTime: Date { dataSource.primaryStartTime }

    private let wingCollapsed = PillLayout.wingCollapsed
    private let wingExpanded = PillLayout.wingExpanded

    /// The concave fillets at the top corners: the pill's walls sit this far in.
    private var wall: CGFloat { hasNotch ? (hovered ? 9 : 6) : 0 }
    /// Wall → text column. Matches the notification cards (24 from the wall).
    private let column: CGFloat = Island.inset + Island.cardPadding

    /// The character reflects whichever session most needs the user.
    private var characterState: CharacterState { CharacterState(session: sessions.first, runway: runway) }

    private var runway: UsageLimitsStore.LimitWindow? {
        limits.sessionWindow(for: sessions.first?.agentSource ?? .claude)
    }

    private var wing: CGFloat { hovered ? wingExpanded : wingCollapsed }
    private var pillWidth: CGFloat { notchWidth + (wing * 2) }
    private var maxWidth: CGFloat { notchWidth + (wingExpanded * 2) }
    private var maxHeight: CGFloat { notchHeight + PillLayout.maxContentHeight }
    private var expandedContentHeight: CGFloat {
        PillLayout.contentHeight(for: sessions, runway: dataSource.showsRunway)
    }
    private var pillTotalHeight: CGFloat { hovered ? (notchHeight + expandedContentHeight) : notchHeight }

    /// With a notch the pill comes out of the hardware itself, so it grows
    /// rather than fades. Without one (or with Reduce Motion) it fades in.
    private var emergesFromNotch: Bool { hasNotch && !reduceMotion }
    /// The mask's width before it's out: the notch's own, so the wings start at
    /// its edges; a touch under full size when there's no notch to come from.
    private var tuckedScale: CGFloat {
        if reduceMotion { return 1 }
        return hasNotch ? notchWidth / pillWidth : 0.95
    }

    var body: some View {
        Group {
            ZStack(alignment: .top) {
                pillShape
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillTotalHeight)

                header()

                if hovered {
                    VStack(spacing: 0) {
                        sessionList()
                        if dataSource.showsRunway {
                            runwayFooter
                        }
                    }
                    .padding(.top, notchHeight + PillLayout.dropTopPad)
                    .padding(.horizontal, wall + Island.inset)
                    .padding(.bottom, PillLayout.dropBottomPad)
                    .frame(width: pillWidth, alignment: .top)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .frame(width: pillWidth, height: pillTotalHeight, alignment: .top)
            // The wings grow out from the notch's own edges (and fold back in);
            // only the mask moves, so nothing inside is ever squashed.
            .mask(pillShape.scaleEffect(x: appeared ? 1 : tuckedScale, y: 1, anchor: .center))
            // Peek sits outside the clip: reaching for you, it swings a little
            // below the notch line, and a hard cut there looks broken.
            .overlay(alignment: .topLeading) { character() }
            .contentShape(pillShape)
            .onTapGesture { onTap(sessions.first?.id) }
            .opacity(appeared || emergesFromNotch ? 1 : 0)
            .animation(Island.spring, value: hovered)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pillAccessibilityLabel)
        }
        .frame(width: maxWidth, height: maxHeight, alignment: .top)
        .onAppear {
            withAnimation(Island.spring) { appeared = true }
        }
        .onChange(of: dataSource.retracted) { _, retracted in
            withAnimation(retracted ? Island.retract : Island.spring) { appeared = !retracted }
        }
        .onChange(of: sessions) { _, _ in activity &+= 1 }
    }

    // MARK: - Header (level with the notch)

    private func header() -> some View {
        HStack(spacing: 0) {
            // Left wing: the character's place (it's drawn above, unclipped).
            Color.clear.frame(width: wing, height: notchHeight)

            Spacer().frame(width: notchWidth)

            // Right wing: runway, read like a battery. The session timer stands
            // in until usage is known (or when it can't be read).
            // Collapsed, it centres in the wing clear of the corner fillet.
            trailingStatus()
                .frame(width: hovered ? nil : wing - wall - 2)
                .padding(.trailing, hovered ? wall + column : wall + 2)
                .frame(width: wing, alignment: .trailing)
        }
        .frame(width: pillWidth, height: notchHeight)
        .opacity(appeared ? 1 : 0)
    }

    /// The character, hanging from the notch edge. Open, it slides to the
    /// text column and looks down at the list. Its view reaches below the
    /// notch so poses that hang lower are never cut off.
    private func character() -> some View {
        CharacterView(
            state: characterState,
            framing: .notch(height: notchHeight),
            gaze: hovered ? SIMD2<Float>(0.03, -0.09) : nil,
            // On screen for hours: resting motion runs at 30 fps, full rate
            // when it wants you, you're looking, or it's doing a trick.
            // Frames that wouldn't visibly change are skipped either way.
            framesPerSecond: (hovered || characterState == .need) ? 60 : PillLayout.restingFPS,
            lively: true,
            activity: activity
        )
        .frame(width: wingCollapsed, height: notchHeight + PillLayout.characterOverhang)
        .allowsHitTesting(false)
        .padding(.leading, hovered ? wall + column - 17 : 0)
        // Out from behind the notch, and back in when the last session ends.
        .offset(x: appeared || !emergesFromNotch ? 0 : wingCollapsed)
    }

    @ViewBuilder
    private func trailingStatus() -> some View {
        if let runway {
            RunwayIndicator(percentLeft: runway.percentLeft, compact: !hovered)
        } else {
            let primary = sessions.first
            let waiting = primary?.status == .needsInput || primary?.status == .needsPermission
            ElapsedText(since: primaryStartTime, compact: true,
                        font: .system(size: hovered ? Island.smallSize : Island.captionSize, weight: .semibold).monospacedDigit(),
                        color: waiting ? CharacterState.need.color : .white.opacity(0.72))
                .accessibilityLabel("Elapsed")
        }
    }

    private var pillShape: AnyShape {
        guard hasNotch else {
            return AnyShape(RoundedRectangle(cornerRadius: hovered ? 24 : notchHeight / 2, style: .continuous))
        }
        return AnyShape(NotchShape(topRadius: wall, bottomRadius: hovered ? 24 : notchHeight / 2))
    }

    private var pillAccessibilityLabel: String {
        guard let primary = sessions.first else { return "Notch So Good" }
        let phase = primary.status.activityLine(toolName: primary.activeToolName, toolDetail: primary.activeToolDetail)
        if sessions.count > 1 {
            return "\(primary.projectName), \(phase). \(sessions.count) sessions active."
        }
        return "\(primary.projectName), \(phase)"
    }

    // MARK: - Session list

    @ViewBuilder
    private func sessionList() -> some View {
        if PillLayout.needsScrolling(sessions) {
            ScrollView(.vertical) { rows() }
                .scrollIndicators(.hidden)
                .frame(height: PillLayout.maxListHeight)
        } else {
            rows()
        }
    }

    private func rows() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(buildRowList().enumerated()), id: \.element.id) { index, row in
                Group {
                    switch row.kind {
                    case .single(let session): sessionRow(session)
                    case .header(let name, let sessions): groupHeader(name, sessions: sessions)
                    case .sub(let session, let group): subSessionRow(session, group: group)
                    case .subagent(let sub): subagentRow(sub)
                    }
                }
                .opacity(hovered ? 1 : 0)
                .offset(y: hovered ? 0 : -4)
                .animation(.brisk.delay(min(Double(index) * 0.02, 0.1)), value: hovered)
            }
        }
    }

    private enum RowKind {
        case single(NotificationManager.SessionInfo)
        case header(String, [NotificationManager.SessionInfo])
        case sub(NotificationManager.SessionInfo, group: String)
        case subagent(NotificationManager.SubagentInfo)
    }

    private struct Row: Identifiable {
        let id: String
        let kind: RowKind
    }

    private func buildRowList() -> [Row] {
        var rows: [Row] = []
        for group in SessionGroup.from(sessions) {
            if group.sessions.count == 1 {
                let session = group.sessions[0]
                rows.append(Row(id: session.id, kind: .single(session)))
                rows += session.subagents.map { Row(id: "sub-\($0.id)", kind: .subagent($0)) }
            } else {
                rows.append(Row(id: "header-\(group.projectName)", kind: .header(group.projectName, group.sessions)))
                for session in group.sessions {
                    rows.append(Row(id: session.id, kind: .sub(session, group: group.projectName)))
                    rows += session.subagents.map { Row(id: "sub-\($0.id)", kind: .subagent($0)) }
                }
            }
        }
        return rows
    }

    /// Row content inset from the list edge so text lands on the column.
    private var rowInset: CGFloat { column - Island.inset }

    /// One session: dot, what it's working on (or the project), and underneath
    /// where and what it's doing right now; elapsed on the right.
    private func sessionRow(_ session: NotificationManager.SessionInfo) -> some View {
        Button { onTap(session.id) } label: {
            IslandSessionRow(session: session)
                .padding(.leading, rowInset - 3.5)
                .padding(.trailing, rowInset)
                .frame(height: PillLayout.sessionRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandRowStyle())
        .accessibilityLabel(SessionRowParts.accessibilityLabel(session))
        .accessibilityHint("Opens this session in its terminal")
    }

    /// Several sessions in one repo: its name, how many, and how many need
    /// you; then a row each, naming its workspace.
    private func groupHeader(_ name: String, sessions: [NotificationManager.SessionInfo]) -> some View {
        let waiting = sessions.filter { $0.status == .needsInput || $0.status == .needsPermission }.count
        return HStack(spacing: 6) {
            Text(name)
                .font(Island.meta.weight(.semibold))
                .foregroundColor(Island.secondary)
                .lineLimit(1)
            Text("\(sessions.count) sessions")
                .font(Island.caption)
                .foregroundColor(Island.tertiary)
            if waiting > 0 {
                Text("· \(waiting) need\(waiting == 1 ? "s" : "") you")
                    .font(Island.caption)
                    .foregroundColor(CharacterState.need.color)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, rowInset)
        .padding(.bottom, 2)
        .frame(height: PillLayout.groupHeader, alignment: .bottom)
        .accessibilityElement(children: .combine)
    }

    private func subSessionRow(_ session: NotificationManager.SessionInfo, group: String) -> some View {
        Button { onTap(session.id) } label: {
            IslandSessionRow(session: session, group: group)
                .padding(.leading, rowInset - 3.5)
                .padding(.trailing, rowInset)
                .frame(height: PillLayout.subSessionRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandRowStyle())
        .accessibilityLabel(SessionRowParts.accessibilityLabel(session))
        .accessibilityHint("Opens this session in its terminal")
    }

    /// A subagent, hung off its parent with a hairline.
    private func subagentRow(_ sub: NotificationManager.SubagentInfo) -> some View {
        HStack(spacing: 7) {
            Path { p in
                p.move(to: CGPoint(x: 0.5, y: 0))
                p.addLine(to: CGPoint(x: 0.5, y: 5))
                p.addQuadCurve(to: CGPoint(x: 7, y: 11), control: CGPoint(x: 0.5, y: 11))
            }
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
            .frame(width: 7, height: 11, alignment: .top)
            .offset(y: -4)
            Circle()
                .fill(sub.status.dotColor.opacity(sub.status == .completed ? 0.6 : 1))
                .frame(width: 5, height: 5)
            Text(sub.description)
                .font(Island.detail)
                .foregroundColor(Island.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ElapsedText(since: sub.startTime)
        }
        .padding(.leading, rowInset + 3)
        .padding(.trailing, rowInset)
        .frame(height: PillLayout.subagentRow)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Runway footer

    private var runwayFooter: some View {
        let window = runway
        let pct = window?.percentLeft ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("5-hour window")
                    .font(Island.caption)
                    .foregroundColor(Island.secondary)
                Spacer(minLength: 6)
                Text("\(pct)% left")
                    .font(Island.numeric)
                    .foregroundColor(Color.white.opacity(0.85))
                if let resets = window?.resetsAt {
                    Text("· resets in \(UsageLimitsStore.resetCountdown(resets))")
                        .font(Island.numeric)
                        .foregroundColor(Island.tertiary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(UsageTint.notch(pct))
                        .frame(width: max(3, g.size.width * CGFloat(min(100, max(0, pct))) / 100))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, rowInset)
        .padding(.top, 13)
        .frame(height: PillLayout.runwayFooter, alignment: .top)
        .overlay(alignment: .top) {
            Rectangle().fill(Island.hairline).frame(height: 1).padding(.horizontal, rowInset)
        }
        .opacity(hovered ? 1 : 0)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Session grouping by project

struct SessionGroup: Identifiable {
    let id: String  // the repo, or the project when it isn't one
    let projectName: String
    let sessions: [NotificationManager.SessionInfo]

    /// Sessions in one repository share a group, its worktrees (Conductor's
    /// workspaces) included; outside a repo, the project folder decides.
    static func from(_ sessions: [NotificationManager.SessionInfo]) -> [SessionGroup] {
        var order: [String] = []
        var map: [String: [NotificationManager.SessionInfo]] = [:]
        for session in sessions {
            let key = session.repoName ?? session.projectName
            if map[key] == nil {
                order.append(key)
            }
            map[key, default: []].append(session)
        }
        return order.compactMap { name in
            guard let sessions = map[name] else { return nil }
            return SessionGroup(id: name, projectName: name, sessions: sessions)
        }
    }
}
