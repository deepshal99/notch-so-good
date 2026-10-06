import SwiftUI

/// Colour for "how much is left": calm while there's room, orange under 25%,
/// red under 10% — the character's own colour language.
enum UsageTint {
    /// In the notch: white on black reads like hardware.
    static func notch(_ percentLeft: Int) -> Color {
        warning(percentLeft) ?? Color.white.opacity(0.92)
    }

    private static func warning(_ percentLeft: Int) -> Color? {
        if percentLeft < 10 { return CharacterState.error.color }
        if percentLeft < 25 { return CharacterState.need.color }
        return nil
    }
}

/// A progress ring: round caps, starts at 12 o'clock, fills clockwise with
/// what's left. Animates between values with the island's spring.
struct UsageRing: View {
    let percentLeft: Int
    var diameter: CGFloat
    var lineWidth: CGFloat
    var tint: Color
    var track = Color.white.opacity(0.14)

    private var fraction: CGFloat { CGFloat(min(100, max(0, percentLeft))) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                // A sliver stays visible at 0% so an empty window still reads as a ring.
                .trim(from: 0, to: max(0.012, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .animation(Island.spring, value: percentLeft)
        .accessibilityHidden(true)
    }
}

/// The notch's runway: a thin ring and the percentage of the 5-hour window left.
struct RunwayIndicator: View {
    let percentLeft: Int
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            UsageRing(percentLeft: percentLeft,
                      diameter: compact ? 10.5 : 12,
                      lineWidth: compact ? 2.3 : 2.5,
                      tint: UsageTint.notch(percentLeft),
                      track: Color.white.opacity(0.2))
            Text("\(percentLeft)%")
                .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(percentLeft < 25 ? UsageTint.notch(percentLeft) : Color.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(value: Double(percentLeft)))
        }
        .animation(Island.spring, value: percentLeft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percentLeft) percent of the 5-hour window left")
    }
}
