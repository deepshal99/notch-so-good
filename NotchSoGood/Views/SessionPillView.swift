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
    private var characterState: CharacterState { CharacterState(session: sessions.first) }

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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .top) {
                pillShape
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillTotalHeight)

                header(now: context.date)

                if hovered {
                    VStack(spacing: 0) {
                        sessionList(now: context.date)
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
            .clipShape(pillShape)
            .contentShape(pillShape)
            .onTapGesture { onTap(sessions.first?.id) }
            .scaleEffect(x: appeared ? 1 : 0.85, y: 1, anchor: .center)
            .animation(Island.spring, value: hovered)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pillAccessibilityLabel)
        }
        .frame(width: maxWidth, height: maxHeight, alignment: .top)
        .onAppear {
            withAnimation(Island.spring) { appeared = true }
        }
    }

    // MARK: - Header (level with the notch)

    private func header(now: Date) -> some View {
        HStack(spacing: 0) {
            // Left wing: the character, hanging from the notch edge. Open, it
            // slides to the text column and looks down at the list.
            CharacterView(
                state: characterState,
                framing: .pill,
                gaze: hovered ? SIMD2<Float>(0.03, -0.09) : nil,
                // On screen for hours: 30 fps while it just works, full rate when
                // it wants you, celebrates, or you're looking.
                framesPerSecond: (hovered || characterState == .need || characterState == .done) ? 60 : 30
            )
            .frame(width: wingCollapsed, height: notchHeight)
            .padding(.leading, hovered ? wall + column - 17 : 0)
            .frame(width: wing, alignment: .leading)

            Spacer().frame(width: notchWidth)

            // Right wing: runway, read like a battery. The session timer stands
            // in until usage is known (or when it can't be read).
            // Collapsed, it centres in the wing clear of the corner fillet.
            trailingStatus(now: now)
                .frame(width: hovered ? nil : wing - wall - 2)
                .padding(.trailing, hovered ? wall + column : wall + 2)
                .frame(width: wing, alignment: .trailing)
        }
        .frame(width: pillWidth, height: notchHeight)
        .opacity(appeared ? 1 : 0)
    }

    @ViewBuilder
    private func trailingStatus(now: Date) -> some View {
        if let runway {
            RunwayIndicator(percentLeft: runway.percentLeft, compact: !hovered)
        } else {
            let primary = sessions.first
            let waiting = primary?.status == .needsInput || primary?.status == .needsPermission
            let elapsed = ElapsedFormatter.compact(Int(now.timeIntervalSince(primaryStartTime)))
            Text(elapsed)
                .font(.system(size: hovered ? 11.5 : 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(waiting ? CharacterState.need.color : .white.opacity(0.72))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Elapsed \(elapsed)")
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
    private func sessionList(now: Date) -> some View {
        if PillLayout.needsScrolling(sessions) {
            ScrollView(.vertical) { rows(now: now) }
                .scrollIndicators(.hidden)
                .frame(height: PillLayout.maxListHeight)
        } else {
            rows(now: now)
        }
    }

    private func rows(now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(buildRowList().enumerated()), id: \.element.id) { index, row in
                Group {
                    switch row.kind {
                    case .single(let session): sessionRow(session, now: now)
                    case .header(let name, let count): groupHeader(name, count: count)
                    case .sub(let session): subSessionRow(session, now: now)
                    case .subagent(let sub): subagentRow(sub, now: now)
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
        case header(String, Int)
        case sub(NotificationManager.SessionInfo)
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
                rows.append(Row(id: "header-\(group.projectName)", kind: .header(group.projectName, group.sessions.count)))
                for session in group.sessions {
                    rows.append(Row(id: session.id, kind: .sub(session)))
                    rows += session.subagents.map { Row(id: "sub-\($0.id)", kind: .subagent($0)) }
                }
            }
        }
        return rows
    }

    /// Row content inset from the list edge so text lands on the column.
    private var rowInset: CGFloat { column - Island.inset }

    /// One session: dot, project, what it's doing; elapsed on the right.
    private func sessionRow(_ session: NotificationManager.SessionInfo, now: Date) -> some View {
        Button { onTap(session.id) } label: {
            HStack(spacing: 8) {
                StatusDot(color: session.status.dotColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.projectName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Island.primary)
                            .lineLimit(1)
                        badges(for: session)
                    }
                    activityText(session)
                }
                Spacer(minLength: 8)
                trailing(session: session, now: now)
            }
            .padding(.leading, rowInset - 3.5)
            .padding(.trailing, rowInset)
            .frame(height: PillLayout.sessionRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(SessionRowStyle())
        .accessibilityLabel(rowAccessibilityLabel(session, now: now))
        .accessibilityHint("Opens this session in its terminal")
    }

    /// Several sessions in one project: a quiet header, then a row each.
    private func groupHeader(_ name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Island.secondary)
                .lineLimit(1)
            Text("\(count) sessions")
                .font(Island.caption)
                .foregroundColor(Island.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, rowInset)
        .padding(.bottom, 4)
        .frame(height: PillLayout.groupHeader, alignment: .bottom)
    }

    private func subSessionRow(_ session: NotificationManager.SessionInfo, now: Date) -> some View {
        Button { onTap(session.id) } label: {
            HStack(spacing: 8) {
                StatusDot(color: session.status.dotColor, size: 6)
                activityText(session, emphasised: true)
                badges(for: session)
                Spacer(minLength: 8)
                trailing(session: session, now: now)
            }
            .padding(.leading, rowInset - 3)
            .padding(.trailing, rowInset)
            .frame(height: PillLayout.subSessionRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(SessionRowStyle())
        .accessibilityLabel(rowAccessibilityLabel(session, now: now))
        .accessibilityHint("Opens this session in its terminal")
    }

    /// A subagent, hung off its parent with a hairline.
    private func subagentRow(_ sub: NotificationManager.SubagentInfo, now: Date) -> some View {
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
                .font(.system(size: 11.5))
                .foregroundColor(Island.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(ElapsedFormatter.precise(Int(now.timeIntervalSince(sub.startTime))))
                .font(Island.numeric)
                .foregroundColor(Island.tertiary)
        }
        .padding(.leading, rowInset + 3)
        .padding(.trailing, rowInset)
        .frame(height: PillLayout.subagentRow)
        .accessibilityElement(children: .combine)
    }

    private func activityText(_ session: NotificationManager.SessionInfo, emphasised: Bool = false) -> some View {
        let waiting = session.status == .needsInput || session.status == .needsPermission
        return Text(session.status.activityLine(toolName: session.activeToolName, toolDetail: session.activeToolDetail))
            .font(.system(size: emphasised ? 12.5 : 11.5, weight: emphasised ? .medium : .regular))
            .foregroundColor(waiting ? session.status.dotColor : (emphasised ? Color.white.opacity(0.82) : Island.secondary))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func badges(for session: NotificationManager.SessionInfo) -> some View {
        if session.agentSource != .claude {
            Chip(text: session.agentSource.displayName, mono: false, tint: session.agentSource.accentColor, height: 17)
        }
        if let mode = session.permissionMode.badgeLabel {
            Chip(text: mode, mono: false, height: 17)
        }
    }

    private func trailing(session: NotificationManager.SessionInfo, now: Date) -> some View {
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
            Text(ElapsedFormatter.precise(Int(now.timeIntervalSince(session.startTime))))
                .font(Island.numeric)
                .foregroundColor(Island.tertiary)
        }
    }

    private func rowAccessibilityLabel(_ session: NotificationManager.SessionInfo, now: Date) -> String {
        let phase = session.status.activityLine(toolName: session.activeToolName, toolDetail: session.activeToolDetail)
        let elapsed = ElapsedFormatter.precise(Int(now.timeIntervalSince(session.startTime)))
        var label = "\(session.projectName), \(session.agentSource.displayName), \(phase), \(elapsed)"
        if let mode = session.permissionMode.badgeLabel { label += ", \(mode) mode" }
        return label
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

// MARK: - Row style

/// A soft highlight on hover, concentric with the island's bottom corners.
private struct SessionRowStyle: ButtonStyle {
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

// MARK: - Session grouping by project

struct SessionGroup: Identifiable {
    let id: String  // projectName
    let projectName: String
    let sessions: [NotificationManager.SessionInfo]

    static func from(_ sessions: [NotificationManager.SessionInfo]) -> [SessionGroup] {
        var order: [String] = []
        var map: [String: [NotificationManager.SessionInfo]] = [:]
        for session in sessions {
            if map[session.projectName] == nil {
                order.append(session.projectName)
            }
            map[session.projectName, default: []].append(session)
        }
        return order.compactMap { name in
            guard let sessions = map[name] else { return nil }
            return SessionGroup(id: name, projectName: name, sessions: sessions)
        }
    }
}
