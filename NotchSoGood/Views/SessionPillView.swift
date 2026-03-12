import SwiftUI

/// A Dynamic Island pill that extends the notch left and right while Claude is active.
/// Left wing: tiny Chawd mascot. Right wing: elapsed timer. Same height as the physical notch.
struct SessionPillView: View {
    let sessionId: String?
    let startTime: Date
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: () -> Void

    @State private var appeared = false
    @State private var hovered = false
    @State private var elapsedText = "0s"

    // How far the pill extends beyond the notch on each side
    private let wingExtension: CGFloat = 44

    private var totalWidth: CGFloat { notchWidth + (wingExtension * 2) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(startTime))
            let elapsed = formatElapsed(seconds)

            ZStack {
                // === SINGLE CONTINUOUS BLACK PILL — spans the full width ===
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: notchHeight / 2,
                    bottomTrailingRadius: notchHeight / 2,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)
                .frame(width: totalWidth, height: notchHeight)

                // === CONTENT — left and right, center stays empty over notch ===
                HStack(spacing: 0) {
                    // Left wing content — Mascot
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        MiniChawdView()
                            .frame(width: 20, height: 20)
                        Spacer(minLength: 0)
                    }
                    .frame(width: wingExtension)
                    .opacity(appeared ? 1 : 0)

                    // Center — empty, the physical notch sits here
                    Spacer()
                        .frame(width: notchWidth)

                    // Right wing content — Timer
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: "4ADE80"))
                            .frame(width: 4, height: 4)
                            .modifier(PulseModifier())

                        Text(elapsed)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(width: wingExtension)
                    .opacity(appeared ? 1 : 0)
                }
                .frame(width: totalWidth, height: notchHeight)
            }
            .frame(width: totalWidth, height: notchHeight)
            .scaleEffect(x: appeared ? 1 : 0.68, y: 1, anchor: .center)
        }
        .onTapGesture(perform: onTap)
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                hovered = h
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

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

// MARK: - Mini Chawd — a tiny pixel-art crab for the pill

struct MiniChawdView: View {
    @State private var breathe = false
    @State private var blink = false
    @State private var blinkTimer: Timer?
    @State private var gimmick: ChawdGimmick = .none
    @State private var gimmickTimer: Timer?
    @State private var danceTick = false
    @State private var waveTick = false

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

            // Left arm stub — waves during .wave gimmick
            let armY: CGFloat = gimmick == .wave ? (waveTick ? -2 : 0) : 1.5
            let armH: CGFloat = gimmick == .wave ? 2.5 : 3
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 0, y: armY, w: 2, h: armH, color: skin)

            // Main body
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 2, y: 0, w: 10, h: 7, color: skin)

            // Top highlight
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 2, y: 0, w: 10, h: 0.8, color: skinLight.opacity(0.3))

            // Eyes
            drawEyes(ctx: ctx, ox: ox, oy: oy, px: px)

            // Mouth
            drawMouth(ctx: ctx, ox: ox, oy: oy, px: px)

            // Legs
            let wiggle: CGFloat = breathe ? 0.1 : 0
            let danceL: CGFloat = gimmick == .dance ? 0.4 : 0
            let danceR: CGFloat = gimmick == .dance ? -0.4 : 0
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL, y: 7, w: 1.5, h: 3, color: skin)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR, y: 7, w: 1.5, h: 3, color: skin)

            // Feet
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 4.5 - wiggle + danceL, y: 9.5, w: 1.5, h: 0.8, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 9 + wiggle + danceR, y: 9.5, w: 1.5, h: 0.8, color: skinDark)

            // Extras
            drawExtras(ctx: ctx, ox: ox, oy: oy, px: px)
        }
        .scaleEffect(breathe ? 1.03 : 1.0)
        .scaleEffect(gimmick == .bounce ? 1.12 : 1.0)
        .offset(y: gimmick == .bounce ? -2 : 0)
        .offset(x: gimmick == .dance ? (danceTick ? 1.5 : -1.5) : 0)
        .rotationEffect(.degrees(gimmick == .dance ? (danceTick ? 5 : -5) : 0))
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
        } else if gimmick == .sparkle || gimmick == .bounce {
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
        } else if gimmick == .bounce || gimmick == .sparkle {
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
        if gimmick == .sparkle {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: -1, y: -1, w: 0.8, h: 0.8, color: .yellow.opacity(0.8))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -1.5, w: 0.8, h: 0.8, color: .yellow.opacity(0.7))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 15, y: 2, w: 0.6, h: 0.6, color: .yellow.opacity(0.5))
        } else if gimmick == .doze {
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 13, y: -1, w: 0.5, h: 0.5, color: .white.opacity(0.25))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 14, y: -3, w: 0.7, h: 0.7, color: .white.opacity(0.3))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 15, y: -5, w: 0.9, h: 0.9, color: .white.opacity(0.35))
        }
    }

    // MARK: - Pixel helper

    private func px_fill(_ ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat,
                         x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color) {
        let rect = CGRect(x: ox + x * px, y: oy + y * px, width: w * px, height: h * px)
        ctx.fill(Path(rect), with: .color(color))
    }

    // MARK: - Blink

    private func startBlink() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            guard gimmick == .none || gimmick == .wave || gimmick == .lookAround else { return }
            withAnimation(.easeInOut(duration: 0.08)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }

    // MARK: - Periodic gimmicks

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

        if picked == .dance {
            doDanceWiggle(count: 4, interval: 0.2)
        }
        if picked == .wave {
            doWavePump(count: 3, interval: 0.2)
        }

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
