import SwiftUI

// MARK: - Spring Presets

extension Animation {
    /// Quick UI responses — hover states, press feedback, small toggles
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 0.7)
    /// Standard transitions — expand/collapse, appear/disappear, layout changes
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// Playful character motion — bounces, wiggles, celebration
    static let bouncy = Animation.spring(response: 0.25, dampingFraction: 0.5)
}

/// A Dynamic Island pill that extends the notch left and right while an AI agent is active.
/// On hover, it expands fluidly to show session details.
struct SessionPillView: View {
    @ObservedObject var dataSource: PillDataSource
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: (String?) -> Void
    @ObservedObject var hoverMonitor: PillHoverMonitor

    @State private var appeared = false
    private var hovered: Bool { hoverMonitor.isHovered }

    private var sessions: [NotificationManager.SessionInfo] { dataSource.sessions }
    private var primaryStartTime: Date { dataSource.primaryStartTime }

    // Collapsed: small wings
    private let wingCollapsed: CGFloat = 56
    // Expanded: wider wings for session detail
    private let wingExpanded: CGFloat = 110
    // Drop-down sizing
    private let dropTopPad: CGFloat = 4
    private let dropBottomPad: CGFloat = 10
    private let sessionRowHeight: CGFloat = 36
    private let groupHeaderHeight: CGFloat = 22
    private let subSessionRowHeight: CGFloat = 32
    private let overflowRowHeight: CGFloat = 20

    // Group sessions by project name for hierarchical display
    private var sessionGroups: [SessionGroup] {
        SessionGroup.from(sessions)
    }

    private let subagentRowHeight: CGFloat = 24

    private var expandedContentHeight: CGFloat {
        var h: CGFloat = dropTopPad + dropBottomPad
        for group in sessionGroups {
            if group.sessions.count == 1 {
                let session = group.sessions[0]
                h += sessionRowHeight
                h += subagentRowHeight * CGFloat(session.subagents.count)
            } else {
                h += groupHeaderHeight
                for session in group.sessions {
                    h += subSessionRowHeight
                    h += subagentRowHeight * CGFloat(session.subagents.count)
                }
            }
        }
        return h
    }

    // Cap max height for the panel (generous to avoid clipping)
    private static let maxContentHeight: CGFloat = 300

    private var wing: CGFloat { hovered ? wingExpanded : wingCollapsed }
    private var pillWidth: CGFloat { notchWidth + (wing * 2) }
    private var maxWidth: CGFloat { notchWidth + (wingExpanded * 2) }
    private var maxHeight: CGFloat { notchHeight + Self.maxContentHeight }
    private var pillTotalHeight: CGFloat { hovered ? (notchHeight + expandedContentHeight) : notchHeight }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(primaryStartTime))
            let elapsed = formatElapsed(seconds)

            ZStack(alignment: .top) {
                // === BLACK PILL SHAPE ===
                pillShape
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillTotalHeight)

                // === WING CONTENT ===
                HStack(spacing: 0) {
                    // Left wing — Mascot
                    // Clip only horizontally so walk disappears behind notch
                    // but hop animation isn't cut off vertically
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        MiniChawdView(excited: hovered)
                            .frame(width: 20, height: 20)
                        Spacer(minLength: 0)
                    }
                    .frame(width: wing)
                    // Clip horizontally (walk disappears at wing edge)
                    // but allow vertical overflow (hop animation)
                    .clipShape(HorizontalOnlyClip())
                    .opacity(appeared ? 1 : 0)

                    Spacer()
                        .frame(width: notchWidth)

                    // Right wing — Phase icon + Timer
                    HStack(spacing: 4) {
                        let primary = sessions.first
                        let primaryStatus = primary?.status ?? .running
                        PhaseIconView(
                            status: primaryStatus,
                            toolName: primary?.activeToolName,
                            size: hovered ? 10 : 8,
                            compact: true
                        )

                        Text(elapsed)
                            .font(.system(size: hovered ? 11 : 10, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.trailing, 6)
                    .frame(width: wing)
                    .opacity(appeared ? 1 : 0)
                }
                .frame(width: pillWidth, height: notchHeight)

                // === EXPANDED SESSION LIST ===
                if hovered {
                    expandedContent(now: context.date)
                        .padding(.top, notchHeight + 4)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .frame(width: pillWidth, alignment: .top)
                        .transition(.opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .frame(width: pillWidth, height: pillTotalHeight, alignment: .top)
            .clipShape(pillShape)
            .contentShape(pillShape)
            .onTapGesture {
                onTap(sessions.first?.id)
            }
            .scaleEffect(x: appeared ? 1 : 0.85, y: 1, anchor: .center)
            .animation(.smooth, value: hovered)
        }
        .frame(width: maxWidth, height: maxHeight, alignment: .top)
        .onAppear {
            withAnimation(.smooth) {
                appeared = true
            }
        }
    }

    // MARK: - Pill shape

    private var pillShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: hovered ? 18 : notchHeight / 2,
            bottomTrailingRadius: hovered ? 18 : notchHeight / 2,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - Expanded content (grouped by project)

    private func expandedContent(now: Date) -> some View {
        VStack(spacing: 0) {
            // Flatten to get stagger index across all rows
            let allRows = buildRowList()
            ForEach(Array(allRows.enumerated()), id: \.element.id) { index, row in
                Group {
                    switch row.kind {
                    case .single(let session):
                        sessionRow(session: session, now: now)
                    case .header(let name):
                        projectHeader(name: name)
                    case .sub(let session):
                        subSessionRow(session: session, now: now)
                    case .subagent(let sub):
                        subagentRow(sub: sub, now: now)
                    }
                }
                .opacity(hovered ? 1 : 0)
                .offset(y: hovered ? 0 : -4)
                .animation(.smooth.delay(Double(index) * 0.035), value: hovered)
            }
        }
    }

    // Row type for stagger enumeration
    private enum ExpandedRowKind {
        case single(NotificationManager.SessionInfo)
        case header(String)
        case sub(NotificationManager.SessionInfo)
        case subagent(NotificationManager.SubagentInfo)
    }

    private struct ExpandedRow: Identifiable {
        let id: String
        let kind: ExpandedRowKind
    }

    private func buildRowList() -> [ExpandedRow] {
        var rows: [ExpandedRow] = []
        for group in sessionGroups {
            if group.sessions.count == 1 {
                let session = group.sessions[0]
                rows.append(ExpandedRow(id: session.id, kind: .single(session)))
                // Add subagent rows under this session
                for sub in session.subagents {
                    rows.append(ExpandedRow(id: "sub-\(sub.id)", kind: .subagent(sub)))
                }
            } else {
                rows.append(ExpandedRow(id: "header-\(group.projectName)", kind: .header(group.projectName)))
                for session in group.sessions {
                    rows.append(ExpandedRow(id: session.id, kind: .sub(session)))
                    for sub in session.subagents {
                        rows.append(ExpandedRow(id: "sub-\(sub.id)", kind: .subagent(sub)))
                    }
                }
            }
        }
        return rows
    }

    // MARK: - Full session row (single session per project)

    private func sessionRow(session: NotificationManager.SessionInfo, now: Date) -> some View {
        Button {
            onTap(session.id)
        } label: {
            HStack(spacing: 8) {
                PhaseIconView(
                    status: session.status,
                    toolName: session.activeToolName,
                    size: 11
                )

                VStack(alignment: .leading, spacing: 1) {
                    let secs = Int(now.timeIntervalSince(session.startTime))

                    HStack(spacing: 4) {
                        Text(session.projectName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)

                        AgentBadge(source: session.agentSource)
                    }

                    HStack(spacing: 4) {
                        Text(formatElapsed(secs))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))

                        Text("·")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.15))

                        Text(session.status.phaseLabel(toolName: session.activeToolName, toolDetail: session.activeToolDetail))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(session.status.dotColor.opacity(0.8))
                            .lineLimit(1)
                            .contentTransition(.interpolate)
                            .animation(.snappy, value: session.status)
                    }
                }

                Spacer(minLength: 4)

                if !session.subagents.isEmpty {
                    SubagentBadge(count: session.subagents.filter { $0.status == .running }.count)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.07)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(SessionRowButtonStyle())
    }

    // MARK: - Project group header

    private func projectHeader(name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Sub-session row (multiple sessions under a project)

    private func subSessionRow(session: NotificationManager.SessionInfo, now: Date) -> some View {
        Button {
            onTap(session.id)
        } label: {
            HStack(spacing: 6) {
                Spacer().frame(width: 6)

                PhaseIconView(
                    status: session.status,
                    toolName: session.activeToolName,
                    size: 9,
                    compact: true
                )

                let secs = Int(now.timeIntervalSince(session.startTime))

                Text(formatElapsed(secs))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Text("·")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.15))

                Text(session.status.phaseLabel(toolName: session.activeToolName, toolDetail: session.activeToolDetail))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(session.status.dotColor.opacity(0.8))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                    .animation(.snappy, value: session.status)

                AgentBadge(source: session.agentSource)

                Spacer(minLength: 4)

                if !session.subagents.isEmpty {
                    SubagentBadge(count: session.subagents.filter { $0.status == .running }.count)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.white.opacity(0.05)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(SessionRowButtonStyle())
    }

    // MARK: - Subagent row (nested under parent session with tree connector)

    private func subagentRow(sub: NotificationManager.SubagentInfo, now: Date) -> some View {
        HStack(spacing: 0) {
            // Tree connector — L-shaped line
            HStack(spacing: 0) {
                Spacer().frame(width: 14)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1, height: 12)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 8, height: 1)
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: 10, height: 13, alignment: .topLeading)
            }

            PhaseIconView(
                status: sub.status,
                size: 8,
                compact: true
            )

            Text(sub.description)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer(minLength: 4)

            let secs = Int(now.timeIntervalSince(sub.startTime))
            Text(formatElapsed(secs))
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .padding(.trailing, 8)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Format

    private func formatElapsed(_ seconds: Int) -> String {
        if seconds < 60 {
            return String(format: "%02ds", seconds)
        } else if seconds < 3600 {
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", seconds % 60))"
        }
    }
}

// MARK: - Session row button style (subtle highlight on hover)

private struct SessionRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isHovered ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .onHover { h in
                withAnimation(.snappy) { isHovered = h }
            }
    }
}

// MARK: - Mini Chawd — a tiny pixel-art crab for the pill

struct MiniChawdView: View {
    var excited: Bool = false
    var forceGimmick: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAlive = false  // guards recursive asyncAfter loops
    @State private var blink = false
    @State private var blinkTimer: Timer?
    @State private var gimmick: ChawdGimmick = .none
    @State private var gimmickTimer: Timer?
    @State private var danceTick = false
    @State private var waveTick = false
    @State private var jumpOffset: CGFloat = 0
    @State private var squashStretch: CGFloat = 1.0  // <1 = squash, >1 = stretch
    @State private var excitedWiggleTimer: Timer?
    @State private var walkOffset: CGFloat = 0
    @State private var walkStep = false
    @State private var walkTimer: Timer?
    @State private var walkPhase: WalkPhase = .idle
    @State private var sneezePhase: SneezePhase = .idle
    @State private var peekOffset: CGFloat = 0
    @State private var strutOffset: CGFloat = 0    // strut left/right
    @State private var nodAngle: Double = 0        // nod tilt
    @State private var shiverOffset: CGFloat = 0   // shiver shake
    @State private var levitateOffset: CGFloat = 0  // levitate up/down
    @State private var levitateScale: CGFloat = 1.0 // shrink as floating away
    @State private var levitateOpacity: Double = 1.0
    @State private var yawnPhase: YawnPhase = .idle
    @State private var hiccupJolt: CGFloat = 0
    @State private var spinAngle: Double = 0
    @State private var stretchScale: CGFloat = 1.0  // vertical stretch for stretch gimmick
    @State private var stretchArmOffset: CGFloat = 0 // arms go up during stretch

    enum YawnPhase {
        case idle, opening, peak, closing
    }

    // idle eye drift kept for Canvas fallback (always 0 now)
    private let idleEyeDrift: CGFloat = 0

    // Drowsiness system — gets sleepy after prolonged idle
    @State private var idleSeconds: Int = 0
    @State private var isDrowsy: Bool = false
    @State private var drowsinessTimer: Timer?
    @State private var wakeUpReaction: Bool = false

    enum SneezePhase {
        case idle, windup, explode, dazed
    }

    enum WalkPhase {
        case idle, walkingRight, behindNotch, walkingLeft, arrived
    }

    private let skin = Color(hex: "C4896C")
    private let skinLight = Color(hex: "D49A7C")
    private let skinDark = Color(hex: "B07A5E")

    enum ChawdGimmick: CaseIterable {
        case none, wave, bounce, lookAround, dance, doze, sparkle, walk, sneeze, peekaboo, strut, nod, shiver, levitate, yawn, hiccup, spin, stretch
    }

    var body: some View {
        Canvas { ctx, size in
            let px: CGFloat = 1.6
            let totalW: CGFloat = 14 * px
            let totalH: CGFloat = 11 * px
            let ox = (size.width - totalW) / 2
            let oy = (size.height - totalH) / 2

            let armY: CGFloat = gimmick == .wave ? (waveTick ? -2 : 0) : (gimmick == .stretch ? stretchArmOffset : 1.5)
            let armH: CGFloat = gimmick == .wave ? 2.5 : 3
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 0, y: armY, w: 2, h: armH, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 2, y: 0, w: 10, h: 7, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 2, y: 0, w: 10, h: 0.8, color: skinLight.opacity(0.3))

            drawEyes(ctx: ctx, ox: ox, oy: oy, px: px)
            drawMouth(ctx: ctx, ox: ox, oy: oy, px: px)

            let wiggle: CGFloat = 0
            let danceL: CGFloat = gimmick == .dance ? 0.25 : 0
            let danceR: CGFloat = gimmick == .dance ? -0.25 : 0
            // Walking legs: alternate forward/back (for walk and strut)
            let isWalking = (gimmick == .walk || gimmick == .strut) && walkStep
            let walkL: CGFloat = isWalking ? -1.0 : 0
            let walkR: CGFloat = isWalking ? 1.0 : 0
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL + walkL, y: 7, w: 1.5, h: 3, color: skin)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR + walkR, y: 7, w: 1.5, h: 3, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL + walkL, y: 9.5, w: 1.5, h: 0.8, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR + walkR, y: 9.5, w: 1.5, h: 0.8, color: skinDark)

            drawExtras(ctx: ctx, ox: ox, oy: oy, px: px)
        }
        .scaleEffect(x: (gimmick == .walk || gimmick == .strut) ? (walkStep ? -1 : 1) * 0.03 + 1 : 1.0,
                     y: 1.0, anchor: .bottom) // subtle sway while walking
        .rotationEffect(.degrees((gimmick == .walk || gimmick == .strut) ? (walkStep ? 3 : -3) : 0))
        .offset(x: walkOffset)
        .scaleEffect(x: 1.0, y: squashStretch, anchor: .bottom)
        .scaleEffect(x: squashStretch > 1 ? 0.92 : (squashStretch < 1 ? 1.1 : 1.0),
                     y: 1.0, anchor: .center)
        // breathing removed — caused visible pulsing
        .scaleEffect(gimmick == .bounce ? 1.12 : 1.0)
        .offset(y: gimmick == .bounce ? -2 : (jumpOffset + peekOffset))
        .offset(x: gimmick == .dance ? (danceTick ? 0.8 : -0.8) : 0)
        .rotationEffect(.degrees(gimmick == .dance ? (danceTick ? 3 : -3) : 0))
        // Strut offset (walk left/right in place)
        .offset(x: strutOffset + shiverOffset)
        // Nod tilt
        .rotationEffect(.degrees(nodAngle))
        // Levitate
        .offset(y: levitateOffset)
        .scaleEffect(levitateScale)
        .opacity(levitateOpacity)
        // Spin
        .rotationEffect(.degrees(spinAngle))
        // Stretch gimmick — vertical elongation
        .scaleEffect(x: 1.0, y: stretchScale, anchor: .bottom)
        // Hiccup jolt
        .offset(y: hiccupJolt)
        // idle sway/bob removed — caused visible jumping
        .onChange(of: excited) { _, isExcited in
            if isExcited {
                cancelWalk()
                cancelGimmickState(animated: true)
                gimmickTimer?.invalidate()
                gimmickTimer = nil
                // Wake-up reaction if drowsy
                if isDrowsy {
                    isDrowsy = false
                    idleSeconds = 0
                    wakeUpReaction = true
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        squashStretch = 1.15
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                        guard isAlive else { return }
                        wakeUpReaction = false
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                            squashStretch = 1.0
                        }
                        startExcitedWiggle()
                    }
                } else {
                    startExcitedWiggle()
                }
            } else {
                stopExcitedWiggle()
            }
        }
        .onAppear {
            isAlive = true
            startBlink()
            startDrowsinessTracker()
            scheduleNextGimmick()
        }
        .onDisappear {
            isAlive = false
            blinkTimer?.invalidate()
            blinkTimer = nil
            gimmickTimer?.invalidate()
            gimmickTimer = nil
            excitedWiggleTimer?.invalidate()
            excitedWiggleTimer = nil
            walkTimer?.invalidate()
            walkTimer = nil
            drowsinessTimer?.invalidate()
            drowsinessTimer = nil
            // mouseTrackTimer removed
        }
    }

    // MARK: - Excited wiggle (happy dance while hovered — no vertical offset)

    private func startExcitedWiggle() {
        guard !reduceMotion else { return }
        danceTick = false
        waveTick = false
        withAnimation(.bouncy) {
            gimmick = .dance
        }
        excitedWiggleTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            guard isAlive else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                danceTick.toggle()
                waveTick = danceTick
            }
        }
    }

    private func stopExcitedWiggle() {
        excitedWiggleTimer?.invalidate()
        excitedWiggleTimer = nil
        withAnimation(.snappy) {
            gimmick = .none
            danceTick = false
            waveTick = false
            squashStretch = 1.0
        }
        // Resume gimmick cycle after hover ends
        scheduleNextGimmick()
    }

    // MARK: - Eyes

    private func drawEyes(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
        if wakeUpReaction {
            // Startled wide eyes on wake-up
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 4.5, y: 1, w: 1.5, h: 3, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 4.8, y: 1.3, w: 0.6, h: 0.6, color: .white.opacity(0.6))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.5, y: 1, w: 1.5, h: 3, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.8, y: 1.3, w: 0.6, h: 0.6, color: .white.opacity(0.6))
            return
        }
        if blink || gimmick == .doze {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.8, w: 1, h: 0.6, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.8, w: 1, h: 0.6, color: .black)
        } else if gimmick == .sneeze {
            if sneezePhase == .windup {
                // Squinting, about to sneeze
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.5, w: 1.2, h: 0.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.5, w: 1.2, h: 0.5, color: .black)
            } else if sneezePhase == .explode {
                // Wide shocked eyes
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 4.5, y: 1.2, w: 1.5, h: 2.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.2, w: 1.5, h: 2.8, color: .black)
            } else {
                // Dazed - spiral eyes (X shape)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.8, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.8, y: 1.8, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.4, y: 2.2, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.6, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.8, y: 2.6, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.8, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.8, y: 1.8, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.4, y: 2.2, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.6, w: 0.4, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.8, y: 2.6, w: 0.4, h: 0.4, color: .black)
            }
        } else if gimmick == .peekaboo {
            if peekOffset > 8 {
                // Hidden — no eyes visible
            } else if peekOffset > 0 {
                // Peeking up — wide surprised eyes
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.2, w: 1.3, h: 2.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.3, y: 1.5, w: 0.7, h: 0.7, color: .white)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.2, w: 1.3, h: 2.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.3, y: 1.5, w: 0.7, h: 0.7, color: .white)
            } else {
                // Back up — happy star eyes
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.2, w: 1.2, h: 0.6, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.8, w: 0.5, h: 1, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.7, y: 1.8, w: 0.5, h: 1, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.2, w: 1.2, h: 0.6, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.8, w: 0.5, h: 1, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.7, y: 1.8, w: 0.5, h: 1, color: .black)
            }
        } else if gimmick == .strut {
            // Strut — eyes look in direction of movement, confident
            let strutEyeShift: CGFloat = strutOffset > 0 ? 0.4 : (strutOffset < 0 ? -0.4 : 0)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5 + strutEyeShift, y: 1.5, w: 0.8, h: 2.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9 + strutEyeShift, y: 1.5, w: 0.8, h: 2.5, color: .black)
        } else if gimmick == .nod {
            // Nod — slightly droopy/relaxed eyes
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2, w: 1, h: 2, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2, w: 1, h: 2, color: .black)
        } else if gimmick == .shiver {
            // Shiver — wide startled eyes
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 4.8, y: 1.3, w: 1.3, h: 2.8, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.1, y: 1.6, w: 0.6, h: 0.6, color: .white.opacity(0.5))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.8, y: 1.3, w: 1.3, h: 2.8, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.1, y: 1.6, w: 0.6, h: 0.6, color: .white.opacity(0.5))
        } else if gimmick == .levitate {
            if levitateOffset > 10 {
                // Coming back from below — wide surprised eyes
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 4.8, y: 1.2, w: 1.3, h: 2.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.1, y: 1.5, w: 0.6, h: 0.6, color: .white.opacity(0.6))
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.8, y: 1.2, w: 1.3, h: 2.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.1, y: 1.5, w: 0.6, h: 0.6, color: .white.opacity(0.6))
            } else {
                // Floating up — zen closed eyes (happy arcs)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.5, w: 1.2, h: 0.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.5, w: 1.2, h: 0.5, color: .black)
            }
        } else if gimmick == .yawn {
            if yawnPhase == .peak {
                // Eyes squeezed shut during yawn peak
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.8, w: 1.2, h: 0.4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.8, w: 1.2, h: 0.4, color: .black)
            } else if yawnPhase == .closing {
                // Drowsy half-open eyes
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.2, w: 0.8, h: 1.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.2, w: 0.8, h: 1.5, color: .black)
            } else {
                // Opening — normal eyes
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.5, w: 0.8, h: 2.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.5, w: 0.8, h: 2.5, color: .black)
            }
        } else if gimmick == .hiccup {
            // Surprised wide eyes during hiccup
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 4.8, y: 1.2, w: 1.3, h: 2.8, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.1, y: 1.5, w: 0.5, h: 0.5, color: .white.opacity(0.5))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.8, y: 1.2, w: 1.3, h: 2.8, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.1, y: 1.5, w: 0.5, h: 0.5, color: .white.opacity(0.5))
        } else if gimmick == .spin {
            // Dizzy spiral eyes during spin
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2, w: 1.2, h: 0.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.4, y: 1.6, w: 0.5, h: 1.2, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2, w: 1.2, h: 0.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.4, y: 1.6, w: 0.5, h: 1.2, color: .black)
        } else if gimmick == .stretch {
            // Eyes closed peacefully during stretch
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.5, w: 1.2, h: 0.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.5, w: 1.2, h: 0.5, color: .black)
        } else if gimmick == .walk {
            // Walking: eyes look in direction of travel
            let eyeShift: CGFloat = walkPhase == .walkingLeft ? -0.5 : 0.5
            if walkPhase == .arrived {
                // Surprised/happy eyes on arrival
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.2, w: 1.2, h: 0.6, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.8, w: 0.5, h: 1, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.7, y: 1.8, w: 0.5, h: 1, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.2, w: 1.2, h: 0.6, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.8, w: 0.5, h: 1, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.7, y: 1.8, w: 0.5, h: 1, color: .black)
            } else {
                // Determined eyes, shifted in walk direction
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 5 + eyeShift, y: 1.5, w: 0.8, h: 2.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9 + eyeShift, y: 1.5, w: 0.8, h: 2.5, color: .black)
            }
        } else if gimmick == .lookAround {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.5, y: 1.5, w: 0.8, h: 2.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 1.5, w: 0.8, h: 2.5, color: .black)
        } else if gimmick == .sparkle || gimmick == .bounce || excited {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 2.2, w: 1.2, h: 0.6, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.8, w: 0.5, h: 1, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5.7, y: 1.8, w: 0.5, h: 1, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 2.2, w: 1.2, h: 0.6, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.8, w: 0.5, h: 1, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.7, y: 1.8, w: 0.5, h: 1, color: .black)
        } else {
            // Static idle eyes
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.5, w: 0.8, h: 2.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.5, w: 0.8, h: 2.5, color: .black)
        }
    }

    // MARK: - Mouth

    private func drawMouth(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
        if gimmick == .sneeze {
            if sneezePhase == .windup {
                // Scrunched mouth
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5.5, w: 1, h: 0.5, color: skinDark)
            } else if sneezePhase == .explode {
                // Wide open mouth
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 4.8, w: 3, h: 2, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5.2, w: 2, h: 1.2, color: Color(hex: "A06850"))
            } else {
                // Dazed wavy mouth
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 5.2, w: 1, h: 0.5, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5.5, w: 1, h: 0.5, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 8, y: 5.2, w: 1, h: 0.5, color: skinDark)
            }
            return
        }
        if gimmick == .peekaboo {
            if peekOffset <= 0 {
                // Happy grin after popping back
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 5.2, w: 3, h: 0.6, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 4, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.3))
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.3))
            }
            return
        }
        if gimmick == .strut {
            // Confident little smirk
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5.2, w: 2, h: 0.5, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.2))
            return
        }
        if gimmick == .nod {
            // Relaxed smile
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 0.6, color: skinDark)
            return
        }
        if gimmick == .shiver {
            // Chattering teeth — wavy mouth
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 5, w: 1, h: 0.6, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5.4, w: 1, h: 0.6, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 8, y: 5, w: 1, h: 0.6, color: skinDark)
            return
        }
        if gimmick == .yawn {
            if yawnPhase == .peak {
                // Wide open yawn mouth
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 4.5, w: 3, h: 2.5, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 1.5, color: Color(hex: "A06850"))
            } else if yawnPhase == .opening {
                // Mouth starting to open
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 1.2, color: skinDark)
            } else {
                // Closing — gentle smile after yawn
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 0.6, color: skinDark)
            }
            return
        }
        if gimmick == .hiccup {
            // Small surprised O mouth
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 4.8, w: 1.5, h: 1.5, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7.3, y: 5.1, w: 0.9, h: 0.9, color: Color(hex: "A06850"))
            return
        }
        if gimmick == .spin {
            // Dizzy open mouth
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5, w: 1.5, h: 1, color: skinDark)
            return
        }
        if gimmick == .stretch {
            // Relaxed smile + blush
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 0.5, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 4, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.25))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.25))
            return
        }
        if gimmick == .levitate {
            if levitateOffset > 10 {
                // Surprised O mouth on return
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 4.8, w: 1.5, h: 1.5, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7.3, y: 5.1, w: 0.9, h: 0.9, color: Color(hex: "A06850"))
            } else {
                // Zen smile while floating
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 0.5, color: skinDark)
                // Blush
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 4, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.25))
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.25))
            }
            return
        }
        if gimmick == .walk {
            if walkPhase == .arrived {
                // Big happy grin on arrival + blush
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 5.2, w: 3, h: 0.6, color: skinDark)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 4, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.3))
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.3))
            } else {
                // Determined little mouth
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5.2, w: 1.5, h: 0.5, color: skinDark)
            }
            return
        }
        if gimmick == .doze {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5, w: 1.2, h: 1, color: skinDark)
        } else if gimmick == .bounce || gimmick == .sparkle || excited {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 6, y: 5.2, w: 3, h: 0.6, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 4, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.3))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 4, w: 1.5, h: 1, color: Color(hex: "E8756B").opacity(0.3))
        } else if gimmick == .dance {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 1.2, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 5.3, w: 1, h: 0.6, color: Color(hex: "A06850"))
        } else {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 6.5, y: 5, w: 2, h: 0.6, color: skinDark)
        }
    }

    // MARK: - Extras

    private func drawExtras(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
        if gimmick == .yawn && yawnPhase == .peak {
            // Teardrop from yawn
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 3.5, w: 0.5, h: 0.8, color: .white.opacity(0.35))
            return
        }
        if gimmick == .stretch {
            // Relaxation sparkles
            px_fill(ctx, ox: ox, oy: oy, px: px, x: -1, y: 0, w: 0.6, h: 0.6, color: .yellow.opacity(0.5))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -1, w: 0.6, h: 0.6, color: .yellow.opacity(0.4))
            return
        }
        if gimmick == .sneeze && sneezePhase == .explode {
            // Sneeze particles flying out
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: 3, w: 0.6, h: 0.6, color: .white.opacity(0.6))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 15, y: 1, w: 0.5, h: 0.5, color: .white.opacity(0.4))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 13, y: 5, w: 0.5, h: 0.5, color: .white.opacity(0.5))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 16, y: 4, w: 0.4, h: 0.4, color: .white.opacity(0.3))
            return
        }
        if gimmick == .strut {
            // Little confidence sparkle
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -1, w: 0.6, h: 0.6, color: .yellow.opacity(0.6))
            return
        }
        if gimmick == .walk && walkPhase == .arrived {
            // Celebration sparkles
            px_fill(ctx, ox: ox, oy: oy, px: px, x: -1, y: -1, w: 0.8, h: 0.8, color: .yellow.opacity(0.8))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -1.5, w: 0.8, h: 0.8, color: .yellow.opacity(0.7))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 15, y: 2, w: 0.6, h: 0.6, color: .yellow.opacity(0.5))
            return
        }
        if gimmick == .sparkle || excited {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: -1, y: -1, w: 0.8, h: 0.8, color: .yellow.opacity(0.8))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -1.5, w: 0.8, h: 0.8, color: .yellow.opacity(0.7))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 15, y: 2, w: 0.6, h: 0.6, color: .yellow.opacity(0.5))
        } else if gimmick == .doze {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 13, y: -1, w: 0.5, h: 0.5, color: .white.opacity(0.25))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -3, w: 0.7, h: 0.7, color: .white.opacity(0.3))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 15, y: -5, w: 0.9, h: 0.9, color: .white.opacity(0.35))
        }
    }

    private func px_fill(_ ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat,
                         x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color) {
        let rect = CGRect(x: ox + x * px, y: oy + y * px, width: w * px, height: h * px)
        ctx.fill(Path(rect), with: .color(color))
    }

    private func startBlink() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            guard isAlive else { return }
            guard gimmick == .none || gimmick == .wave || gimmick == .lookAround else { return }
            withAnimation(.easeInOut(duration: 0.08)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard isAlive else { return }
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }

    // MARK: - Drowsiness system

    private func startDrowsinessTracker() {
        drowsinessTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [self] _ in
            guard isAlive else { return }
            // Reset counter when excited (hovered)
            if excited {
                idleSeconds = 0
                if isDrowsy {
                    isDrowsy = false
                }
                return
            }
            idleSeconds += 10
            // Become drowsy after ~2 minutes of idle (±30s fuzz — precise thresholds feel robotic)
            let drowsinessThreshold = 120 + Int.random(in: -30...30)
            if idleSeconds >= drowsinessThreshold && !isDrowsy {
                isDrowsy = true
            }
        }
    }

    @State private var isFirstGimmick = true

    private func scheduleNextGimmick() {
        guard isAlive else { return }
        // Respect reduced motion — keep breathing but skip gimmicks
        guard !reduceMotion || forceGimmick != nil else { return }
        let delay: Double
        if forceGimmick != nil && isFirstGimmick {
            delay = 0.3  // fire immediately on first appear for demo/preview
            isFirstGimmick = false
        } else if forceGimmick != nil {
            delay = 3.0
        } else {
            delay = isDrowsy ? Double.random(in: 8...14) : Double.random(in: 5...10)
        }
        gimmickTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            guard isAlive else { return }
            performRandomGimmick()
        }
    }

    @State private var lastGimmick: ChawdGimmick = .none

    private func performRandomGimmick() {
        var picked: ChawdGimmick
        if let force = forceGimmick,
           let match = ChawdGimmick.allCases.first(where: { "\($0)" == force }) {
            picked = match
        } else if isDrowsy {
            let sleepyOptions: [ChawdGimmick] = [.doze, .doze, .doze, .yawn, .yawn, .nod, .stretch]
            picked = sleepyOptions.randomElement() ?? .doze
        } else {
            let options: [ChawdGimmick] = [.wave, .bounce, .lookAround, .dance, .doze, .sparkle, .walk, .sneeze, .peekaboo, .strut, .nod, .shiver, .levitate, .yawn, .hiccup, .spin, .stretch]
            picked = options.randomElement() ?? .wave
        }
        // Avoid repeating the same gimmick twice (feels mechanical)
        if picked == lastGimmick && forceGimmick == nil {
            let fallbacks: [ChawdGimmick] = [.wave, .bounce, .lookAround, .sparkle, .nod]
            picked = fallbacks.randomElement() ?? .wave
        }
        lastGimmick = picked

        // Personality-matched spring for each gimmick entrance
        func enterSpring(_ r: Double, _ d: Double) -> Animation {
            .spring(response: r, dampingFraction: d)
        }

        // Each gimmick gets a spring that matches its personality
        switch picked {
        case .walk:
            withAnimation(enterSpring(0.3, 0.65)) { gimmick = .walk }
            doWalk()
            return
        case .strut:
            withAnimation(enterSpring(0.25, 0.6)) { gimmick = .strut }
            doStrut()
            return
        case .nod:
            withAnimation(enterSpring(0.4, 0.75)) { gimmick = .nod } // relaxed
            doNod()
            return
        case .shiver:
            withAnimation(enterSpring(0.15, 0.4)) { gimmick = .shiver } // snappy
            doShiver()
            return
        case .levitate:
            withAnimation(enterSpring(0.5, 0.7)) { gimmick = .levitate } // floaty
            doLevitate()
            return
        case .yawn:
            withAnimation(enterSpring(0.5, 0.8)) { gimmick = .yawn } // lazy
            doYawn()
            return
        case .hiccup:
            withAnimation(enterSpring(0.12, 0.3)) { gimmick = .hiccup } // snappy
            doHiccup()
            return
        case .spin:
            withAnimation(enterSpring(0.2, 0.45)) { gimmick = .spin } // bouncy
            doSpin()
            return
        case .stretch:
            withAnimation(enterSpring(0.45, 0.7)) { gimmick = .stretch } // luxurious
            doStretch()
            return
        case .sneeze:
            withAnimation(enterSpring(0.25, 0.5)) { gimmick = .sneeze }
            doSneeze()
            return
        case .peekaboo:
            withAnimation(enterSpring(0.3, 0.55)) { gimmick = .peekaboo }
            doPeekaboo()
            return
        default:
            break
        }

        let duration: Double
        switch picked {
        case .wave: duration = 1.2
        case .bounce: duration = 0.8
        case .lookAround: duration = 1.5
        case .dance: duration = 1.6
        case .doze: duration = 3.0  // longer — dozing should feel lazy
        case .sparkle: duration = 1.4
        default: duration = 0
        }

        withAnimation(.bouncy) {
            gimmick = picked
        }

        if picked == .dance { doDanceWiggle(count: 4, interval: 0.2) }
        if picked == .wave { doWavePump(count: 3, interval: 0.2) }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            guard isAlive else { return }
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    private func doDanceWiggle(count: Int, interval: Double) {
        guard count > 0, isAlive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard isAlive else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                danceTick.toggle()
            }
            doDanceWiggle(count: count - 1, interval: interval)
        }
    }

    private func doWavePump(count: Int, interval: Double) {
        guard count > 0, isAlive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard isAlive else { return }
            withAnimation(.spring(response: 0.12, dampingFraction: 0.4)) {
                waveTick.toggle()
            }
            doWavePump(count: count - 1, interval: interval)
        }
    }

    // MARK: - Strut animation (walk left a few steps, then right, like showing off)

    private func doStrut() {
        startWalkSteps()

        // Phase 1: Walk left a couple steps
        withAnimation(.easeInOut(duration: 0.6)) {
            strutOffset = -6
        }

        // Phase 2: Pause, look around
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard self.isAlive else { return }
            stopWalkSteps()
        }

        // Phase 3: Walk right past center
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard self.isAlive else { return }
            startWalkSteps()
            withAnimation(.easeInOut(duration: 0.8)) {
                strutOffset = 6
            }
        }

        // Phase 4: Pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard self.isAlive else { return }
            stopWalkSteps()
        }

        // Phase 5: Walk back to center
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard self.isAlive else { return }
            startWalkSteps()
            withAnimation(.easeInOut(duration: 0.5)) {
                strutOffset = 0
            }
        }

        // Phase 6: Stop and settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            guard self.isAlive else { return }
            stopWalkSteps()
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
            guard isAlive else { return }
            gimmick = .none
            strutOffset = 0
            scheduleNextGimmick()
        }
    }

    // MARK: - Nod animation (gentle head bob like agreeing or dozing)

    private func doNod() {
        // Nod down
        withAnimation(.easeInOut(duration: 0.3)) {
            nodAngle = 8
            squashStretch = 0.95
        }

        // Back up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard self.isAlive else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                nodAngle = -2
                squashStretch = 1.0
            }
        }

        // Second nod (smaller)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard self.isAlive else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                nodAngle = 5
                squashStretch = 0.97
            }
        }

        // Settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard self.isAlive else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                nodAngle = 0
                squashStretch = 1.0
            }
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            guard isAlive else { return }
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    // MARK: - Shiver animation (quick shaking like a chill ran through)

    private func doShiver() {
        doShiverShake(count: 6, interval: 0.08)

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            guard isAlive else { return }
            shiverOffset = 0
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    private func doShiverShake(count: Int, interval: Double) {
        guard count > 0, isAlive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard self.isAlive else { return }
            withAnimation(.linear(duration: 0.06)) {
                shiverOffset = count % 2 == 0 ? 1.2 : -1.2
            }
            doShiverShake(count: count - 1, interval: interval)
        }
    }

    // MARK: - Levitate animation (float up and away, reappear from bottom)

    private func doLevitate() {
        // Phase 1: Gentle lift-off — rise slowly, shrink slightly
        withAnimation(.easeIn(duration: 0.8)) {
            levitateOffset = -8
            levitateScale = 0.9
        }

        // Phase 2: Accelerate upward and fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.isAlive else { return }
            withAnimation(.easeIn(duration: 0.5)) {
                levitateOffset = -25
                levitateScale = 0.6
                levitateOpacity = 0
            }
        }

        // Phase 3: Teleport to below (invisible)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard self.isAlive else { return }
            withAnimation(.none) {
                levitateOffset = 25
                levitateScale = 0.6
            }
        }

        // Phase 4: Rise up from bottom, surprised!
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            guard self.isAlive else { return }
            withAnimation(.none) {
                levitateOpacity = 1.0
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                levitateOffset = -2
                levitateScale = 1.05
            }
        }

        // Phase 5: Settle bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                levitateOffset = 0
                levitateScale = 1.0
            }
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [self] in
            guard isAlive else { return }
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    // MARK: - Yawn animation (mouth opens wide, eyes squeeze, stretches tall)

    private func doYawn() {
        yawnPhase = .opening

        // Phase 1: Mouth starts opening, slight stretch up
        withAnimation(.easeIn(duration: 0.5)) {
            squashStretch = 1.08
        }

        // Phase 2: Peak yawn — eyes shut, mouth wide, max stretch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.isAlive else { return }
            yawnPhase = .peak
            withAnimation(.easeInOut(duration: 0.4)) {
                squashStretch = 1.15
            }
        }

        // Phase 3: Hold peak
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard self.isAlive else { return }
            yawnPhase = .closing
            withAnimation(.easeOut(duration: 0.5)) {
                squashStretch = 0.95
            }
        }

        // Phase 4: Settle back with a sigh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                squashStretch = 1.0
            }
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [self] in
            guard isAlive else { return }
            yawnPhase = .idle
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    // MARK: - Hiccup animation (quick jolts upward, 3 times)

    private func doHiccup() {
        doOneHiccup(remaining: 3, delay: 0)
    }

    private func doOneHiccup(remaining: Int, delay: Double) {
        guard remaining > 0, isAlive else {
            // End after all hiccups
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [self] in
                guard isAlive else { return }
                gimmick = .none
                hiccupJolt = 0
                scheduleNextGimmick()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.isAlive else { return }
            // Jolt up
            withAnimation(.spring(response: 0.08, dampingFraction: 0.3)) {
                hiccupJolt = -3
                squashStretch = 1.1
            }

            // Settle back
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard self.isAlive else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    hiccupJolt = 0
                    squashStretch = 1.0
                }
            }

            // Next hiccup
            self.doOneHiccup(remaining: remaining - 1, delay: 0.45)
        }
    }

    // MARK: - Spin animation (full 360 rotation with bounce landing)

    private func doSpin() {
        // Wind up — slight crouch
        withAnimation(.easeIn(duration: 0.15)) {
            squashStretch = 0.88
            jumpOffset = 0.5
        }

        // Launch + spin
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.isAlive else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                jumpOffset = -3
                squashStretch = 1.05
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                spinAngle = 360
            }
        }

        // Land
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.45)) {
                jumpOffset = 0
                squashStretch = 0.85
            }
        }

        // Bounce recover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                squashStretch = 1.0
            }
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [self] in
            guard isAlive else { return }
            gimmick = .none
            spinAngle = 0
            scheduleNextGimmick()
        }
    }

    // MARK: - Stretch animation (arms up, body elongates, relaxes)

    private func doStretch() {
        // Phase 1: Arms rise, body starts stretching
        withAnimation(.easeInOut(duration: 0.6)) {
            stretchArmOffset = -3  // arms go up
            stretchScale = 1.15
        }

        // Phase 2: Hold the stretch, slight wobble
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard self.isAlive else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                stretchScale = 1.12
            }
        }

        // Phase 3: Peak stretch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard self.isAlive else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                stretchScale = 1.18
            }
        }

        // Phase 4: Release — arms drop, body relaxes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                stretchArmOffset = 0
                stretchScale = 0.95
            }
        }

        // Phase 5: Settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                stretchScale = 1.0
            }
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [self] in
            guard isAlive else { return }
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    // MARK: - Sneeze animation

    private func doSneeze() {
        sneezePhase = .windup

        // Phase 1: Wind up — squash down, scrunching
        withAnimation(.easeIn(duration: 0.5)) {
            squashStretch = 0.85
            jumpOffset = 1
        }

        // Phase 2: Bigger wind up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.isAlive else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                squashStretch = 0.75
                jumpOffset = 1.5
            }
        }

        // Phase 3: EXPLODE! — stretch tall, jump, particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard self.isAlive else { return }
            sneezePhase = .explode
            withAnimation(.spring(response: 0.12, dampingFraction: 0.3)) {
                squashStretch = 1.25
                jumpOffset = -2.5
            }
        }

        // Phase 4: Recoil back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                squashStretch = 0.9
                jumpOffset = 0
            }
        }

        // Phase 5: Dazed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            guard self.isAlive else { return }
            sneezePhase = .dazed
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                squashStretch = 1.0
            }
        }

        // Phase 6: Recover + end
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            guard isAlive else { return }
            sneezePhase = .idle
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    // MARK: - Peek-a-boo animation

    private func doPeekaboo() {
        // Phase 1: Sink down below the pill edge
        withAnimation(.easeIn(duration: 0.4)) {
            peekOffset = 14
        }

        // Phase 2: Pause while hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard self.isAlive else { return }
            // Phase 3: Peek up slowly (just eyes visible)
            withAnimation(.easeOut(duration: 0.4)) {
                peekOffset = 5
            }
        }

        // Phase 4: Pause peeking
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard self.isAlive else { return }
            // Phase 5: Pop back up with bounce!
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                peekOffset = 0
            }
        }

        // Phase 6: Little celebration bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                squashStretch = 0.85
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                squashStretch = 1.0
            }
        }

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [self] in
            guard isAlive else { return }
            gimmick = .none
            scheduleNextGimmick()
        }
    }

    // MARK: - Walk animation

    private func cancelWalk() {
        walkTimer?.invalidate()
        walkTimer = nil
        walkPhase = .idle
        walkOffset = 0
        gimmick = .none
    }

    private func cancelGimmickState(animated: Bool = false) {
        sneezePhase = .idle
        yawnPhase = .idle
        if animated {
            withAnimation(.smooth) {
                levitateOpacity = 1.0
                levitateScale = 1.0
                peekOffset = 0
                strutOffset = 0
                nodAngle = 0
                shiverOffset = 0
                levitateOffset = 0
                squashStretch = 1.0
                jumpOffset = 0
                hiccupJolt = 0
                spinAngle = 0
                stretchScale = 1.0
                stretchArmOffset = 0
            }
        } else {
            levitateOpacity = 1.0
            levitateScale = 1.0
            peekOffset = 0
            strutOffset = 0
            nodAngle = 0
            shiverOffset = 0
            levitateOffset = 0
            squashStretch = 1.0
            jumpOffset = 0
            hiccupJolt = 0
            spinAngle = 0
            stretchScale = 1.0
            stretchArmOffset = 0
        }
    }

    private func doWalk() {
        walkPhase = .walkingRight
        startWalkSteps()

        // Phase 1: Walk right → disappear behind notch (~1.2s)
        withAnimation(.easeIn(duration: 1.2)) {
            walkOffset = 40
        }

        // Phase 2: Behind notch — stop steps, teleport to left
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [self] in
            guard isAlive, gimmick == .walk else { return }
            walkPhase = .behindNotch
            stopWalkSteps()

            // Instantly jump to far left (off-screen)
            withAnimation(.none) {
                walkOffset = -40
            }

            // Phase 3: Walk left → center (~1.2s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                guard isAlive, gimmick == .walk else { return }
                walkPhase = .walkingLeft
                startWalkSteps()

                withAnimation(.easeOut(duration: 1.0)) {
                    walkOffset = 0
                }

                // Phase 4: Arrived! Celebration
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                    guard isAlive, gimmick == .walk else { return }
                    stopWalkSteps()
                    walkPhase = .arrived

                    // Little bounce on arrival
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                        squashStretch = 0.85
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard self.isAlive else { return }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                            squashStretch = 1.0
                        }
                    }

                    // End walk gimmick after celebration
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                        guard isAlive else { return }
                        walkPhase = .idle
                        gimmick = .none
                        scheduleNextGimmick()
                    }
                }
            }
        }
    }

    private func startWalkSteps() {
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            guard isAlive else { return }
            walkStep.toggle()
        }
    }

    private func stopWalkSteps() {
        walkTimer?.invalidate()
        walkTimer = nil
        walkStep = false
    }
}

// MARK: - Horizontal-only clip (preserves vertical overflow for hop)

private struct HorizontalOnlyClip: Shape {
    func path(in rect: CGRect) -> Path {
        // Match the view's width but extend far vertically
        Path(CGRect(x: rect.minX, y: rect.minY - 200, width: rect.width, height: rect.height + 400))
    }
}

// MARK: - Pulse animation modifier

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

// MARK: - Agent source badge (tiny pill showing Claude/Codex)

struct AgentBadge: View {
    let source: AgentSource

    var body: some View {
        Text(source.displayName)
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .foregroundColor(source.accentColor.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(source.accentColor.opacity(0.12))
            )
    }
}

private struct PulseModifier: ViewModifier {
    var disabled: Bool = false
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(disabled ? 1.0 : (pulse ? 0.4 : 1.0))
            .animation(disabled ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                if !disabled { pulse = true }
            }
    }
}
