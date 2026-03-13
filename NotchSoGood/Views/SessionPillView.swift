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

    private var sessions: [(id: String, startTime: Date)] { dataSource.sessions }
    private var primaryStartTime: Date { dataSource.primaryStartTime }

    // Collapsed: small wings
    private let wingCollapsed: CGFloat = 56
    // Expanded: wider wings for session detail
    private let wingExpanded: CGFloat = 110
    // Drop-down height below the notch on hover
    private var dropHeight: CGFloat {
        let topPad: CGFloat = 4
        let bottomPad: CGFloat = 10
        let rowHeight: CGFloat = 36
        let count = CGFloat(min(sessions.count, 4))
        return topPad + bottomPad + (rowHeight * max(count, 1))
    }

    private var wing: CGFloat { hovered ? wingExpanded : wingCollapsed }
    private var pillWidth: CGFloat { notchWidth + (wing * 2) }
    private var maxWidth: CGFloat { notchWidth + (wingExpanded * 2) }
    private var maxHeight: CGFloat { notchHeight + 16 + (36 * 4) + 6 }
    private var pillTotalHeight: CGFloat { hovered ? (notchHeight + dropHeight) : notchHeight }

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
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        MiniChawdView(excited: hovered)
                            .frame(width: 20, height: 20)
                        Spacer(minLength: 0)
                    }
                    .frame(width: wing)
                    .opacity(appeared ? 1 : 0)

                    Spacer()
                        .frame(width: notchWidth)

                    // Right wing — Timer
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: "4ADE80"))
                            .frame(width: hovered ? 5 : 4, height: hovered ? 5 : 4)
                            .modifier(PulseModifier())

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

    // MARK: - Expanded content

    private func expandedContent(now: Date) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(sessions.prefix(4).enumerated()), id: \.offset) { index, session in
                sessionRow(session: session, now: now)
            }
            if sessions.count > 4 {
                Text("+\(sessions.count - 4) more")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
    }

    private func sessionRow(session: (id: String, startTime: Date), now: Date) -> some View {
        Button {
            onTap(session.id)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: "4ADE80"))
                    .frame(width: 5, height: 5)

                VStack(alignment: .leading, spacing: 1) {
                    let secs = Int(now.timeIntervalSince(session.startTime))
                    let label = session.id.isEmpty || session.id == "test-session"
                        ? "Claude Session"
                        : String(session.id.prefix(12)) + (session.id.count > 12 ? "…" : "")

                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)

                    Text(formatElapsed(secs))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
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

    private let skin = Color(hex: "C4896C")
    private let skinLight = Color(hex: "D49A7C")
    private let skinDark = Color(hex: "B07A5E")

    enum ChawdGimmick: CaseIterable {
        case none, wave, bounce, lookAround, dance, doze, sparkle
    }

    var body: some View {
        Canvas { ctx, size in
            let px: CGFloat = 1.6
            let totalW: CGFloat = 14 * px
            let totalH: CGFloat = 11 * px
            let ox = (size.width - totalW) / 2
            let oy = (size.height - totalH) / 2

            let armY: CGFloat = gimmick == .wave ? (waveTick ? -2 : 0) : 1.5
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
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL, y: 7, w: 1.5, h: 3, color: skin)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR, y: 7, w: 1.5, h: 3, color: skin)

            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL, y: 9.5, w: 1.5, h: 0.8, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR, y: 9.5, w: 1.5, h: 0.8, color: skinDark)

            drawExtras(ctx: ctx, ox: ox, oy: oy, px: px)
        }
        .scaleEffect(x: 1.0, y: squashStretch, anchor: .bottom)
        .scaleEffect(x: squashStretch > 1 ? 0.92 : (squashStretch < 1 ? 1.1 : 1.0),
                     y: 1.0, anchor: .center) // wide on squash, narrow on stretch
        .scaleEffect(breathe ? 1.03 : 1.0)
        .scaleEffect(gimmick == .bounce ? 1.12 : 1.0)
        .offset(y: gimmick == .bounce ? -2 : jumpOffset)
        .offset(x: gimmick == .dance ? (danceTick ? 1.5 : -1.5) : 0)
        .rotationEffect(.degrees(gimmick == .dance ? (danceTick ? 5 : -5) : 0))
        .onChange(of: excited) { _, isExcited in
            if isExcited {
                startHopping()
            } else {
                stopHopping()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = true
            }
            startBlink()
            scheduleNextGimmick()
        }
        .onDisappear {
            blinkTimer?.invalidate()
            blinkTimer = nil
            gimmickTimer?.invalidate()
            gimmickTimer = nil
            hopTimer?.invalidate()
            hopTimer = nil
        }
    }

    // MARK: - Excited hopping (repeating while hovered)

    private func startHopping() {
        doOneHop()
        hopTimer = Timer.scheduledTimer(withTimeInterval: 0.95, repeats: true) { _ in
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
        // Phase 1: Anticipation squash (crouch down)
        withAnimation(.easeIn(duration: 0.12)) {
            squashStretch = 0.82
            jumpOffset = 1
        }

        // Phase 2: Launch up (stretch tall, fly up)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.18)) {
                squashStretch = 1.12
                jumpOffset = -4.5
            }
        }

        // Phase 3: Airborne (hang at peak)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeInOut(duration: 0.12)) {
                squashStretch = 1.0
                jumpOffset = -4
            }
        }

        // Phase 4: Fall down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.easeIn(duration: 0.14)) {
                squashStretch = 1.03
                jumpOffset = 0
            }
        }

        // Phase 5: Landing squash (absorb impact)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.45)) {
                squashStretch = 0.86
                jumpOffset = 0.5
            }
        }

        // Phase 6: Recover to neutral
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
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
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 1.5, w: 0.8, h: 2.5, color: .black)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 1.5, w: 0.8, h: 2.5, color: .black)
        }
    }

    // MARK: - Mouth

    private func drawMouth(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
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
            guard gimmick == .none || gimmick == .wave || gimmick == .lookAround else { return }
            withAnimation(.easeInOut(duration: 0.08)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }

    private func scheduleNextGimmick() {
        let delay = Double.random(in: 4...8)
        gimmickTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            performRandomGimmick()
        }
    }

    private func performRandomGimmick() {
        let options: [ChawdGimmick] = [.wave, .bounce, .lookAround, .dance, .doze, .sparkle]
        let picked = options.randomElement() ?? .wave

        let duration: Double
        switch picked {
        case .wave: duration = 1.2
        case .bounce: duration = 0.8
        case .lookAround: duration = 1.5
        case .dance: duration = 1.6
        case .doze: duration = 2.5
        case .sparkle: duration = 1.4
        case .none: duration = 0
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            gimmick = picked
        }

        if picked == .dance { doDanceWiggle(count: 4, interval: 0.2) }
        if picked == .wave { doWavePump(count: 3, interval: 0.2) }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gimmick = .none
            }
            scheduleNextGimmick()
        }
    }

    private func doDanceWiggle(count: Int, interval: Double) {
        guard count > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                danceTick.toggle()
            }
            doDanceWiggle(count: count - 1, interval: interval)
        }
    }

    private func doWavePump(count: Int, interval: Double) {
        guard count > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            withAnimation(.spring(response: 0.12, dampingFraction: 0.4)) {
                waveTick.toggle()
            }
            doWavePump(count: count - 1, interval: interval)
        }
    }
}

// MARK: - Pulse animation modifier

private struct PulseModifier: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
