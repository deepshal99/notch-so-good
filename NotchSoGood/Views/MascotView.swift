import SwiftUI

enum MascotExpression {
    case happy, thinking, alert, waving
}

/// Claude's pixel-art mascot — the exact Chawd character with expression variants
struct MascotView: View {
    let expression: MascotExpression
    @State private var breathe = false
    @State private var blink = false
    @State private var armWave: CGFloat = 0
    @State private var bounce: CGFloat = 0
    @State private var blinkTimer: Timer?

    // The exact Chawd color from the reference
    private let skin = Color(hex: "C4896C")
    private let skinLight = Color(hex: "D49A7C")
    private let skinDark = Color(hex: "B07A5E")

    var body: some View {
        ZStack {
            // Glow underneath
            Ellipse()
                .fill(glowColor.opacity(0.15))
                .frame(width: 44, height: 10)
                .blur(radius: 5)
                .offset(y: 20)

            chawdCanvas
                .frame(width: 56, height: 46)
                .scaleEffect(breathe ? 1.02 : 1.0)
                .offset(y: bounce)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = true
            }
            startBlink()
            if expression == .happy {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    bounce = -2
                }
            }
            if expression == .waving {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                    armWave = -4
                }
            }
        }
        .onDisappear {
            blinkTimer?.invalidate()
            blinkTimer = nil
        }
    }

    private var chawdCanvas: some View {
        Canvas { ctx, size in
            // Pixel grid: each "pixel" is this many points
            let px: CGFloat = 3.0

            // The chawd is drawn on a grid. Reference image analysis:
            // Body: 14px wide × 8px tall (at grid scale)
            // Left arm: 3px wide × 4px tall, attached at top-left
            // Eyes: 1px wide × 3px tall, black, positioned inside body
            // Legs: 2px wide × 3px tall, two legs with gap
            //
            // Total grid: ~18px wide × 14px tall
            // Center in the frame
            let totalW: CGFloat = 18 * px
            let totalH: CGFloat = 15 * px
            let ox = (size.width - totalW) / 2
            let oy = (size.height - totalH) / 2

            // === LEFT ARM / STUB ===
            let armOffset: CGFloat = expression == .waving ? armWave : 0
            px_fill(ctx, ox: ox, oy: oy + armOffset, px: px,
                    x: 0, y: 2, w: 3, h: 4, color: skin)

            // === MAIN BODY ===
            // The body is the large rectangle
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 3, y: 0, w: 14, h: 9, color: skin)

            // Subtle highlight on top edge of body
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 3, y: 0, w: 14, h: 1, color: skinLight.opacity(0.3))

            // === EYES ===
            drawEyes(ctx: ctx, ox: ox, oy: oy, px: px)

            // === MOUTH (expression-dependent) ===
            drawMouth(ctx: ctx, ox: ox, oy: oy, px: px)

            // === LEGS ===
            // Two legs hanging from bottom of body, matching reference positions
            let legWiggle: CGFloat = breathe ? 0.15 : 0
            // Left leg
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 6 - legWiggle, y: 9, w: 2, h: 4, color: skin)
            // Right leg
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 12 + legWiggle, y: 9, w: 2, h: 4, color: skin)

            // Feet (tiny darker caps)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 6 - legWiggle, y: 12, w: 2, h: 1, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px,
                    x: 12 + legWiggle, y: 12, w: 2, h: 1, color: skinDark)

            // === EXPRESSION EXTRAS ===
            drawExtras(ctx: ctx, ox: ox, oy: oy, px: px)
        }
    }

    // MARK: - Eyes

    private func drawEyes(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
        switch expression {
        case .happy:
            if blink {
                // Blink: horizontal line
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 3.5, w: 2, h: 0.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 3.5, w: 2, h: 0.8, color: .black)
            } else {
                // Happy squint eyes — inverted U shapes (just shorter eyes + arc feel)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 2.5, w: 2, h: 0.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 2, w: 0.8, h: 1.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.2, y: 2, w: 0.8, h: 1.5, color: .black)

                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 2.5, w: 2, h: 0.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 2, w: 0.8, h: 1.5, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 13.2, y: 2, w: 0.8, h: 1.5, color: .black)
            }
        case .thinking:
            if blink {
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 3.5, w: 1, h: 0.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 3.5, w: 1, h: 0.8, color: .black)
            } else {
                // Normal eyes but pupils shifted right (looking away thinking)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7.5, y: 2, w: 1, h: 3, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12.5, y: 2, w: 1, h: 3, color: .black)
            }
        case .alert:
            if blink {
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 3, w: 1.5, h: 0.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 3, w: 1.5, h: 0.8, color: .black)
            } else {
                // Wide eyes (taller than normal)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 1.5, w: 1.5, h: 4, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 1.5, w: 1.5, h: 4, color: .black)
                // Tiny white highlight
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 1.5, w: 0.6, h: 0.6, color: .white.opacity(0.6))
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 1.5, w: 0.6, h: 0.6, color: .white.opacity(0.6))
            }
        case .waving:
            if blink {
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 3.5, w: 1, h: 0.8, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 3.5, w: 1, h: 0.8, color: .black)
            } else {
                // Default eyes — exact match to reference (1px wide, 3px tall vertical slits)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 7, y: 2, w: 1, h: 3, color: .black)
                px_fill(ctx, ox: ox, oy: oy, px: px, x: 12, y: 2, w: 1, h: 3, color: .black)
            }
        }
    }

    // MARK: - Mouth

    private func drawMouth(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
        switch expression {
        case .happy:
            // Little smile line
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 8.5, y: 6.5, w: 3, h: 0.8, color: skinDark)
            // Cheek blush
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 5, y: 5, w: 2, h: 1.5, color: Color(hex: "E8756B").opacity(0.25))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 13.5, y: 5, w: 2, h: 1.5, color: Color(hex: "E8756B").opacity(0.25))
        case .thinking:
            // Small wavy mouth
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 6.5, w: 1.5, h: 0.8, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 10.5, y: 7, w: 1.5, h: 0.8, color: skinDark)
        case .alert:
            // Small O mouth
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9.5, y: 6, w: 2, h: 2, color: skinDark)
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 10, y: 6.5, w: 1, h: 1, color: Color(hex: "A06850"))
        case .waving:
            // Gentle smile
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 9, y: 6.5, w: 2.5, h: 0.8, color: skinDark)
        }
    }

    // MARK: - Extras (sparkles, thought bubbles, etc)

    private func drawExtras(ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat) {
        switch expression {
        case .happy:
            // Sparkles
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 1, y: 0, w: 1, h: 1, color: .yellow.opacity(0.7))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 17.5, y: -1, w: 1, h: 1, color: .yellow.opacity(0.7))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 18.5, y: 2, w: 0.8, h: 0.8, color: .yellow.opacity(0.5))
        case .thinking:
            // Thought dots rising from top-right
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 16, y: -1, w: 1, h: 1, color: .white.opacity(0.3))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 17.5, y: -3, w: 1.3, h: 1.3, color: .white.opacity(0.35))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 18.5, y: -5.5, w: 1.6, h: 1.6, color: .white.opacity(0.4))
        case .alert:
            // Exclamation above
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 10, y: -4, w: 1, h: 2.5, color: Color(hex: "FB923C"))
            px_fill(ctx, ox: ox, oy: oy, px: px, x: 10, y: -1, w: 1, h: 1, color: Color(hex: "FB923C"))
        case .waving:
            break
        }
    }

    // MARK: - Pixel drawing helper

    private func px_fill(_ ctx: GraphicsContext, ox: CGFloat, oy: CGFloat, px: CGFloat,
                         x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color) {
        let rect = CGRect(x: ox + x * px, y: oy + y * px, width: w * px, height: h * px)
        ctx.fill(Path(rect), with: .color(color))
    }

    // MARK: - Glow color per expression

    private var glowColor: Color {
        switch expression {
        case .happy: return Color(hex: "4ADE80")
        case .thinking: return Color(hex: "60A5FA")
        case .alert: return Color(hex: "FB923C")
        case .waving: return Color(hex: "C084FC")
        }
    }

    // MARK: - Blink timer

    private func startBlink() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.08)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
