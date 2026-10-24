import SwiftUI

/// The island's design language in one place. Every surface that drops out of
/// the notch (cards, the session list) and the popover draw from these, so a
/// title or a hairline is the same everywhere.
///
/// Radii are concentric: a nested shape's radius plus its inset equals its
/// parent's radius. That's what makes the card inside the island read as one
/// object rather than a box placed in a box.
enum Island {
    // MARK: Spacing

    /// Island edge → inner card.
    static let inset: CGFloat = 10
    /// Inner card edge → its content.
    static let cardPadding: CGFloat = 14
    /// Island edge → content, where there's no inner card. The same column
    /// as the inner card's content, so text lines up across every card type.
    static let contentInset: CGFloat = inset + cardPadding

    // MARK: Radii

    static let cardRadius: CGFloat = 20
    /// The island's bottom corners: concentric with the inner card.
    static let radius: CGFloat = cardRadius + inset
    static let wellRadius: CGFloat = 11
    static let chipRadius: CGFloat = 6

    // MARK: Surfaces

    static let card = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.085)
    static let well = Color.black.opacity(0.5)
    static let control = Color.white.opacity(0.1)
    static let controlHover = Color.white.opacity(0.15)

    // MARK: Text

    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.38)

    // MARK: Type

    /// One scale for every surface: 11 · 12 · 13 · 15. Reading text sits at
    /// 13; labels and second lines a step down at 12; the smallest marks
    /// (hints, counts, chips) at 11; titles a clear step up at 15. Nothing
    /// in between, so two texts either match or plainly differ.
    static let captionSize: CGFloat = 11
    static let smallSize: CGFloat = 12
    static let bodySize: CGFloat = 13
    static let titleSize: CGFloat = 15
    /// Code reads larger than prose at the same size, so it takes the small step.
    static let monoSize: CGFloat = smallSize

    static let title = Font.system(size: titleSize, weight: .semibold)
    /// A row's or an option's name.
    static let heading = Font.system(size: bodySize, weight: .semibold)
    static let body = Font.system(size: bodySize)
    static let button = heading
    static let meta = Font.system(size: smallSize, weight: .medium)
    /// Second lines: where a session is, what an option means.
    static let detail = Font.system(size: smallSize)
    static let caption = Font.system(size: captionSize, weight: .medium)
    static let mono = Font.system(size: monoSize, design: .monospaced)
    static let chip = Font.system(size: captionSize, weight: .medium, design: .monospaced)
    static let numeric = Font.system(size: smallSize, weight: .medium).monospacedDigit()
    /// SF Symbols set beside small text.
    static let glyph = Font.system(size: 10, weight: .semibold)

    // MARK: Motion

    /// One clean overshoot: the island's only spring.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    /// Folding back into the notch: quicker than the way out, no overshoot.
    static let retract = Animation.spring(response: 0.28, dampingFraction: 0.9)
    /// Presses: quick, no bounce.
    static let press = Animation.easeOut(duration: 0.15)
}

// MARK: - Shared pieces

/// A status dot with a soft halo, the same mark in cards and the session list.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.22)).frame(width: size*2, height: size*2))
            .frame(width: size*2, height: size*2)
            .accessibilityHidden(true)
    }
}

/// Which agent a session is, in the mark its own terminal shows: Claude
/// Code's ✻, Codex's >_, Gemini's ✦. Drawn, not typed, so all three share one
/// weight; one quiet tone, so Peek stays the only colour in the notch. While
/// the agent works the mark moves: the spark turns, the cursor blinks, the
/// sparkle breathes.
struct AgentMark: View {
    let agent: AgentSource
    var working = false
    var size: CGFloat = 12
    var color: Color = Island.secondary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if working && !reduceMotion {
                TimelineView(.animation(minimumInterval: agent == .codex ? 0.5 : 1/30)) { ctx in
                    mark(t: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                mark(t: nil)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: max(1.4, size*0.14), lineCap: .round, lineJoin: .round) }

    @ViewBuilder
    private func mark(t: TimeInterval?) -> some View {
        switch agent {
        case .claude:
            AgentSpark().stroke(color, style: stroke)
                .rotationEffect(.degrees(t.map { $0 * 90 } ?? 0))
        case .codex:
            ZStack {
                AgentPrompt(part: .chevron).stroke(color, style: stroke)
                AgentPrompt(part: .cursor).stroke(color, style: stroke)
                    .opacity(t.map { Int($0 / 0.5) % 2 == 0 ? 1 : 0.15 } ?? 1)
            }
        case .gemini:
            AgentSparkle().fill(color)
                .scaleEffect(t.map { 0.86 + 0.14 * cos($0 * 3) } ?? 1)
        case .unknown:
            Circle().fill(color).frame(width: size*0.4, height: size*0.4)
        }
    }
}

/// Claude Code's ✻: six spokes from an open centre.
private struct AgentSpark: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height)/2
        var p = Path()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi/3 - .pi/2
            p.move(to: CGPoint(x: c.x + cos(a)*r*0.3, y: c.y + sin(a)*r*0.3))
            p.addLine(to: CGPoint(x: c.x + cos(a)*r*0.88, y: c.y + sin(a)*r*0.88))
        }
        return p
    }
}

/// Codex's >_, in two parts so the cursor can blink.
private struct AgentPrompt: Shape {
    enum Part { case chevron, cursor }
    let part: Part

    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x*rect.width, y: rect.minY + y*rect.height) }
        var p = Path()
        switch part {
        case .chevron:
            p.move(to: pt(0.1, 0.24)); p.addLine(to: pt(0.4, 0.5)); p.addLine(to: pt(0.1, 0.76))
        case .cursor:
            p.move(to: pt(0.54, 0.78)); p.addLine(to: pt(0.92, 0.78))
        }
        return p
    }
}

/// Gemini's ✦: four points, curving in between.
private struct AgentSparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height)/2
        let tips = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
        var p = Path()
        p.move(to: tips[0])
        for i in 1...4 { p.addQuadCurve(to: tips[i % 4], control: c) }
        p.closeSubpath()
        return p
    }
}

/// A mono tag on a quiet fill: "Bash", a branch, an agent.
struct Chip: View {
    let text: String
    var mono = true
    var tint: Color? = nil
    var height: CGFloat = 20

    var body: some View {
        let small = height < 20
        Text(text)
            .font(mono ? Island.chip : Island.caption)
            .foregroundColor(tint ?? Color.white.opacity(0.8))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, small ? 6 : 7)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Island.chipRadius, style: .continuous)
                    .fill((tint ?? .white).opacity(tint == nil ? 0.08 : 0.14))
            )
    }
}

/// Branch glyph + name, truncated in the middle so both ends stay readable.
struct BranchLabel: View {
    let branch: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(Island.glyph)
            Text(branch)
                .font(Island.chip)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(Island.tertiary)
        .accessibilityLabel("branch \(branch)")
    }
}

/// Press feedback shared by every island control: scale 0.96 for 150 ms.
struct IslandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Island.press, value: configuration.isPressed)
    }
}
