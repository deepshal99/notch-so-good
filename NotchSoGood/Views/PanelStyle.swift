import SwiftUI

/// The language of the app's own windows (the menu bar panel and Settings):
/// the island's, carried onto a surface. Near-black, soft cards with a hairline
/// edge, an icon column, white-pill controls and a soft-blue switch. Always
/// dark, whatever the system appearance, so it never reads as a different app.
enum Panel {
    // The island's own materials: pure black, and its inner-card surface.
    static let background = Color.black
    static let card = Island.card
    static let cardEdge = Island.hairline
    static let separator = Color.white.opacity(0.07)
    static let cardRadius: CGFloat = Island.cardRadius
    static let rowPadding: CGFloat = 14
    static let iconColumn: CGFloat = 22

    static let title = Font.system(size: 13, weight: .medium)
    static let subtitle = Font.system(size: 11.5)
    static let sectionTitle = Font.system(size: 12, weight: .medium)

    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.36)
    static let icon = Color.white.opacity(0.6)
    /// The switch and selection colour: the island's working blue.
    static let accent = Color(hex: "7DB8FF")
}

// MARK: - Structure

/// A titled group: quiet title outside, rows inside one card.
struct PanelSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(Panel.sectionTitle)
                    .foregroundColor(Panel.secondary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            PanelCard { content }
        }
    }
}

struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Panel.cardRadius, style: .continuous)
                    .fill(Panel.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Panel.cardRadius, style: .continuous)
                            .strokeBorder(Panel.cardEdge, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Panel.cardRadius, style: .continuous))
    }
}

/// Hairline between rows, aligned with the row text (past the icon column).
struct PanelDivider: View {
    var inset: CGFloat = Panel.rowPadding + Panel.iconColumn + 12

    var body: some View {
        Rectangle().fill(Panel.separator).frame(height: 1).padding(.leading, inset)
    }
}

/// Icon, title and a line of explanation; the control sits on the right.
struct PanelRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Panel.icon)
                .frame(width: Panel.iconColumn)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Panel.title)
                    .foregroundColor(Panel.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(Panel.subtitle)
                        .foregroundColor(Panel.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, Panel.rowPadding)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

extension PanelRow where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Controls

/// The switch: soft blue when on, a quiet track when off.
struct PanelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Island.spring) { configuration.isOn.toggle() }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Panel.accent : Color.white.opacity(0.14))
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A white pill riding a dark capsule track.
struct PanelSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let selected = value == selection
                Button {
                    withAnimation(Island.spring) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundColor(selected ? .black : Panel.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// Capsule buttons: outline for actions, white for the one that matters,
/// quiet (text until hovered) for secondary ones.
struct PanelButtonStyle: ButtonStyle {
    enum Kind { case outline, primary, quiet }
    var kind: Kind = .outline
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(kind == .primary ? .black : (kind == .quiet && !hovered ? Panel.secondary : Panel.primary))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule().fill(kind == .primary ? Color.white.opacity(hovered ? 1 : 0.94)
                               : Color.white.opacity(hovered ? 0.08 : 0))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(kind == .outline ? 0.16 : 0), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Island.press, value: configuration.isPressed)
            .onHover { hovered = $0 }
            .contentShape(Capsule())
    }
}
