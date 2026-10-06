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

    static let titleSize: CGFloat = 14
    static let bodySize: CGFloat = 12.5
    static let monoSize: CGFloat = 12

    static let title = Font.system(size: titleSize, weight: .semibold)
    static let body = Font.system(size: bodySize)
    static let meta = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: monoSize, design: .monospaced)
    static let chip = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let button = Font.system(size: 12.5, weight: .semibold)
    static let numeric = Font.system(size: 11.5, weight: .medium).monospacedDigit()

    // MARK: Sessions

    /// One colour per session, so several running at once stay tellable apart
    /// at a glance. Soft on black, and none of them the orange that means
    /// "needs you".
    static let sessionColors: [Color] = [
        Color(hex: "7DB8FF"), Color(hex: "5FD4C4"), Color(hex: "B79CFF"), Color(hex: "FF8FB8"),
        Color(hex: "FFD166"), Color(hex: "A3E36F"), Color(hex: "E59CFF"), Color(hex: "D9C3A0"),
    ]

    // MARK: Motion

    /// One clean overshoot: the island's only spring.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
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

/// A mono tag on a quiet fill: "Bash", a branch, an agent.
struct Chip: View {
    let text: String
    var mono = true
    var tint: Color? = nil
    var height: CGFloat = 20

    var body: some View {
        let small = height < 20
        Text(text)
            .font(.system(size: small ? 10.5 : 11, weight: .medium, design: mono ? .monospaced : .default))
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
                .font(.system(size: 10, weight: .medium))
            Text(branch)
                .font(.system(size: 11.5, design: .monospaced))
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
