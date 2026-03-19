import SwiftUI

/// A Dynamic Island pill that extends the notch left and right while Claude is active.
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

    private var expandedContentHeight: CGFloat {
        var h: CGFloat = dropTopPad + dropBottomPad
        for group in sessionGroups {
            if group.sessions.count == 1 {
                h += sessionRowHeight
            } else {
                h += groupHeaderHeight + (subSessionRowHeight * CGFloat(group.sessions.count))
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

                    // Right wing — Timer + status dot
                    HStack(spacing: 5) {
                        let primaryStatus = sessions.first?.status ?? .running
                        Circle()
                            .fill(primaryStatus.dotColor)
                            .frame(width: hovered ? 5 : 4, height: hovered ? 5 : 4)
                            .modifier(primaryStatus.shouldPulse ? PulseModifier() : PulseModifier(disabled: true))

                        Text(elapsed)
                            .font(.system(size: hovered ? 11 : 10, weight: .semibold, design: .monospaced))
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
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .frame(width: pillWidth, height: pillTotalHeight, alignment: .top)
            .contentShape(pillShape)
            .onTapGesture {
                onTap(sessions.first?.id)
            }
            .scaleEffect(x: appeared ? 1 : 0.68, y: 1, anchor: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: hovered)
        }
        .frame(width: maxWidth, height: maxHeight, alignment: .top)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
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
            ForEach(sessionGroups) { group in
                if group.sessions.count == 1 {
                    // Single session — flat row with project name
                    sessionRow(session: group.sessions[0], now: now)
                } else {
                    // Multiple sessions — project header + indented sub-rows
                    projectHeader(name: group.projectName)
                    ForEach(group.sessions, id: \.id) { session in
                        subSessionRow(session: session, now: now)
                    }
                }
            }
        }
    }

    // MARK: - Full session row (single session per project)

    private func sessionRow(session: NotificationManager.SessionInfo, now: Date) -> some View {
        Button {
            onTap(session.id)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.status.dotColor)
                    .frame(width: 5, height: 5)
                    .modifier(PulseModifier(disabled: !session.status.shouldPulse))

                VStack(alignment: .leading, spacing: 1) {
                    let secs = Int(now.timeIntervalSince(session.startTime))

                    Text(session.projectName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(formatElapsed(secs))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))

                        if let statusLabel = session.status.label {
                            Text("·")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.2))
                            Text(statusLabel)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(session.status.dotColor.opacity(0.8))
                        }
                    }
                }

                Spacer(minLength: 4)

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
                // Indent to align under project header text
                Spacer().frame(width: 6)

                Circle()
                    .fill(session.status.dotColor)
                    .frame(width: 5, height: 5)
                    .modifier(PulseModifier(disabled: !session.status.shouldPulse))

                // Short session ID for identification
                Text(String(session.id.prefix(6)))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))

                let secs = Int(now.timeIntervalSince(session.startTime))

                Text(formatElapsed(secs))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                if let statusLabel = session.status.label {
                    Text("·")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.15))
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(session.status.dotColor.opacity(0.8))
                }

                Spacer(minLength: 4)

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

    // MARK: - Format

    private func formatElapsed(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
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
                withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
            }
    }
}

// MARK: - Mini Chawd — a tiny pixel-art crab for the pill

struct MiniChawdView: View {
    var excited: Bool = false
    var forceGimmick: String? = nil

    @State private var isAlive = false  // guards recursive asyncAfter loops
    @State private var breathe = false
    @State private var blink = false
    @State private var blinkTimer: Timer?
    @State private var gimmick: ChawdGimmick = .none
    @State private var gimmickTimer: Timer?
    @State private var danceTick = false
    @State private var waveTick = false
    @State private var jumpOffset: CGFloat = 0
    @State private var squashStretch: CGFloat = 1.0  // <1 = squash, >1 = stretch
    @State private var hopTimer: Timer?
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

    // Subtle idle animations
    @State private var idleSway: Double = 0       // gentle rotation
    @State private var idleBob: CGFloat = 0       // tiny vertical float
    @State private var idleLegSwing: CGFloat = 0  // leg dangling
    @State private var idleEyeDrift: CGFloat = 0  // eye wander
    @State private var idleArmTwitch: CGFloat = 0 // arm micro-movement

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
        case none, wave, bounce, lookAround, dance, doze, sparkle, walk, sneeze, peekaboo, strut, nod, shiver, levitate
    }

    var body: some View {
        Canvas { ctx, size in
            let px: CGFloat = 1.6
            let totalW: CGFloat = 14 * px
            let totalH: CGFloat = 11 * px
            let ox = (size.width - totalW) / 2
            let oy = (size.height - totalH) / 2

            let armY: CGFloat = gimmick == .wave ? (waveTick ? -2 : 0) : (1.5 + (gimmick == .none ? idleArmTwitch : 0))
            let armH: CGFloat = gimmick == .wave ? 2.5 : 3
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 0, y: armY, w: 2, h: armH, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 2, y: 0, w: 10, h: 7, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 2, y: 0, w: 10, h: 0.8, color: skinLight.opacity(0.3))

            drawEyes(ctx: ctx, ox: ox, oy: oy, px: px)
            drawMouth(ctx: ctx, ox: ox, oy: oy, px: px)

            let wiggle: CGFloat = breathe ? 0.1 : 0
            let danceL: CGFloat = gimmick == .dance ? 0.4 : 0
            let danceR: CGFloat = gimmick == .dance ? -0.4 : 0
            // Walking legs: alternate forward/back (for walk and strut)
            let isWalking = (gimmick == .walk || gimmick == .strut) && walkStep
            let walkL: CGFloat = isWalking ? -1.0 : 0
            let walkR: CGFloat = isWalking ? 1.0 : 0
            // Idle leg dangle — legs swing slightly out of phase
            let legDangleL: CGFloat = gimmick == .none ? idleLegSwing : 0
            let legDangleR: CGFloat = gimmick == .none ? -idleLegSwing * 0.7 : 0
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL + walkL + legDangleL, y: 7, w: 1.5, h: 3, color: skin)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR + walkR + legDangleR, y: 7, w: 1.5, h: 3, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL + walkL + legDangleL, y: 9.5, w: 1.5, h: 0.8, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR + walkR + legDangleR, y: 9.5, w: 1.5, h: 0.8, color: skinDark)

            drawExtras(ctx: ctx, ox: ox, oy: oy, px: px)
        }
        .scaleEffect(x: (gimmick == .walk || gimmick == .strut) ? (walkStep ? -1 : 1) * 0.03 + 1 : 1.0,
                     y: 1.0, anchor: .bottom) // subtle sway while walking
        .rotationEffect(.degrees((gimmick == .walk || gimmick == .strut) ? (walkStep ? 3 : -3) : 0))
        .offset(x: walkOffset)
        .scaleEffect(x: 1.0, y: squashStretch, anchor: .bottom)
        .scaleEffect(x: squashStretch > 1 ? 0.92 : (squashStretch < 1 ? 1.1 : 1.0),
                     y: 1.0, anchor: .center)
        .scaleEffect(breathe ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: breathe)
        .scaleEffect(gimmick == .bounce ? 1.12 : 1.0)
        .offset(y: gimmick == .bounce ? -2 : (jumpOffset + peekOffset))
        .offset(x: gimmick == .dance ? (danceTick ? 1.5 : -1.5) : 0)
        .rotationEffect(.degrees(gimmick == .dance ? (danceTick ? 5 : -5) : 0))
        // Strut offset (walk left/right in place)
        .offset(x: strutOffset + shiverOffset)
        // Nod tilt
        .rotationEffect(.degrees(nodAngle))
        // Levitate
        .offset(y: levitateOffset)
        .scaleEffect(levitateScale)
        .opacity(levitateOpacity)
        // Subtle idle animations — always running, give life between gimmicks
        .rotationEffect(.degrees(gimmick == .none && !excited ? idleSway : 0))
        .offset(y: gimmick == .none && !excited ? idleBob : 0)
        .onChange(of: excited) { _, isExcited in
            if isExcited {
                cancelWalk()
                cancelGimmickState()
                startHopping()
            } else {
                stopHopping()
            }
        }
        .onAppear {
            isAlive = true
            breathe = true
            startBlink()
            startIdleAnimations()
            scheduleNextGimmick()
        }
        .onDisappear {
            isAlive = false
            blinkTimer?.invalidate()
            blinkTimer = nil
            gimmickTimer?.invalidate()
            gimmickTimer = nil
            hopTimer?.invalidate()
            hopTimer = nil
            walkTimer?.invalidate()
            walkTimer = nil
        }
    }

    // MARK: - Excited hopping (repeating while hovered)

    private func startHopping() {
        doOneHop()
        hopTimer = Timer.scheduledTimer(withTimeInterval: 0.95, repeats: true) { _ in
            guard isAlive else { return }
            doOneHop()
        }
    }

    private func stopHopping() {
        hopTimer?.invalidate()
        hopTimer = nil
        // Settle back to ground
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            jumpOffset = 0
            squashStretch = 1.0
        }
    }

    private func doOneHop() {
        guard isAlive else { return }
        // Phase 1: Anticipation squash (crouch down)
        withAnimation(.easeIn(duration: 0.12)) {
            squashStretch = 0.82
            jumpOffset = 1
        }

        // Phase 2: Launch up (stretch tall, fly up)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard self.isAlive else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                squashStretch = 1.12
                jumpOffset = -4.5
            }
        }

        // Phase 3: Airborne (hang at peak)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            guard self.isAlive else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                squashStretch = 1.0
                jumpOffset = -4
            }
        }

        // Phase 4: Fall down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard self.isAlive else { return }
            withAnimation(.easeIn(duration: 0.14)) {
                squashStretch = 1.03
                jumpOffset = 0
            }
        }

        // Phase 5: Landing squash (absorb impact)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.45)) {
                squashStretch = 0.86
                jumpOffset = 0.5
            }
        }

        // Phase 6: Recover to neutral
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
            guard self.isAlive else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.55)) {
                squashStretch = 1.0
                jumpOffset = 0
            }
        }
    }

    // MARK: - Eyes

    private func drawEyes(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
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
            // Idle eyes with subtle drift
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5 + idleEyeDrift, y: 1.5, w: 0.8, h: 2.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9 + idleEyeDrift, y: 1.5, w: 0.8, h: 2.5, color: .black)
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

    // MARK: - Subtle idle animations (always running, give life between gimmicks)

    private func startIdleAnimations() {
        // Gentle sway — very slow rotation oscillation
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            idleSway = 1.8
        }

        // Vertical bob — float up, dangle down, come back up (looping)
        startIdleBob()

        // Leg dangle — swinging like sitting on a ledge
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            idleLegSwing = 0.35
        }

        // Arm micro-twitch — subtle shift every few seconds
        startArmTwitch()

        // Eye wander — occasional subtle drift
        startEyeWander()
    }

    private func startIdleBob() {
        guard isAlive else { return }
        // Float up
        withAnimation(.easeInOut(duration: 1.5)) {
            idleBob = -1.2
        }
        // Sink down past resting (dangle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard isAlive else { return }
            withAnimation(.easeInOut(duration: 1.8)) {
                idleBob = 0.8
            }
        }
        // Come back up to rest
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
            guard isAlive else { return }
            withAnimation(.easeInOut(duration: 1.2)) {
                idleBob = 0
            }
        }
        // Loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) { [self] in
            startIdleBob()
        }
    }

    private func startArmTwitch() {
        guard isAlive else { return }
        let delay = Double.random(in: 2.5...5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard isAlive else { return }
            guard gimmick == .none else {
                startArmTwitch()
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                idleArmTwitch = CGFloat.random(in: -0.4...0.3)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard isAlive else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    idleArmTwitch = 0
                }
            }
            startArmTwitch()
        }
    }

    private func startEyeWander() {
        guard isAlive else { return }
        let delay = Double.random(in: 2.0...4.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard isAlive else { return }
            guard gimmick == .none else {
                startEyeWander()
                return
            }
            withAnimation(.easeInOut(duration: 0.4)) {
                idleEyeDrift = CGFloat.random(in: -0.5...0.5)
            }
            // Hold the glance briefly, then drift back
            let holdDuration = Double.random(in: 0.8...1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                guard isAlive else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    idleEyeDrift = 0
                }
            }
            startEyeWander()
        }
    }

    private func scheduleNextGimmick() {
        guard isAlive else { return }
        let delay = forceGimmick != nil ? 3.0 : Double.random(in: 3...6)
        gimmickTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            guard isAlive else { return }
            performRandomGimmick()
        }
    }

    private func performRandomGimmick() {
        let picked: ChawdGimmick
        if let force = forceGimmick,
           let match = ChawdGimmick.allCases.first(where: { "\($0)" == force }) {
            picked = match
        } else {
            let options: [ChawdGimmick] = [.wave, .bounce, .lookAround, .dance, .doze, .sparkle, .walk, .sneeze, .peekaboo, .strut, .nod, .shiver, .levitate]
            picked = options.randomElement() ?? .wave
        }

        // These gimmicks handle their own lifecycle
        switch picked {
        case .walk:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .walk }
            doWalk()
            return
        case .strut:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .strut }
            doStrut()
            return
        case .nod:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .nod }
            doNod()
            return
        case .shiver:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .shiver }
            doShiver()
            return
        case .levitate:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .levitate }
            doLevitate()
            return
        case .sneeze:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .sneeze }
            doSneeze()
            return
        case .peekaboo:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gimmick = .peekaboo }
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
        case .doze: duration = 2.5
        case .sparkle: duration = 1.4
        default: duration = 0
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            gimmick = picked
        }

        if picked == .dance { doDanceWiggle(count: 4, interval: 0.2) }
        if picked == .wave { doWavePump(count: 3, interval: 0.2) }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            guard isAlive else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
                strutOffset = 0
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
            }
            scheduleNextGimmick()
        }
    }

    // MARK: - Shiver animation (quick shaking like a chill ran through)

    private func doShiver() {
        doShiverShake(count: 6, interval: 0.08)

        // End
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            guard isAlive else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                shiverOffset = 0
                gimmick = .none
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
            }
            scheduleNextGimmick()
        }
    }

    // MARK: - Walk animation

    private func cancelWalk() {
        walkTimer?.invalidate()
        walkTimer = nil
        walkPhase = .idle
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            walkOffset = 0
            gimmick = .none
        }
    }

    private func cancelGimmickState() {
        sneezePhase = .idle
        levitateOpacity = 1.0
        levitateScale = 1.0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            peekOffset = 0
            strutOffset = 0
            nodAngle = 0
            shiverOffset = 0
            levitateOffset = 0
            squashStretch = 1.0
            jumpOffset = 0
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            gimmick = .none
                        }
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
