import SwiftUI

/// A character in a little square of screen with a sliver of notch to hang
/// from — the app's icon-sized portrait, used in settings and the popover.
struct NotchTile: View {
    let state: CharacterState
    var kind: CharacterKind? = nil
    let size: CGFloat
    var radius: CGFloat = 12
    var framing: CharacterFraming = .tile
    /// Live Metal, or a still frame. Menu bar windows never composite a live
    /// Metal layer (the character stayed blank there), so the menu uses a still.
    var live = true

    var body: some View {
        Group {
            if live {
                CharacterView(state: state, framing: framing, kind: kind, framesPerSecond: 30)
            } else {
                CharacterStill(state: state, kind: kind, framing: framing, size: size)
            }
        }
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(hex: "16161A"), Color(hex: "0B0B0D")], startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: size*0.07, bottomTrailingRadius: size*0.07, style: .continuous)
                    .fill(Color.black)
                    .frame(width: size*0.46, height: size*0.08)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A rendered still of the character, redrawn whenever the character, finish
/// or state changes. Renders off the main thread.
struct CharacterStill: View {
    let state: CharacterState
    var kind: CharacterKind? = nil
    let framing: CharacterFraming
    let size: CGFloat

    @ObservedObject private var settings = CharacterSettings.shared
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    private var resolvedKind: CharacterKind { kind ?? settings.kind }

    /// A moment in each state where the pose reads best as a still.
    private var moment: Double {
        switch state {
        case .done: return 0.6
        case .idle: return 1.0
        default: return 1.4
        }
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            }
        }
        .task(id: "\(resolvedKind.rawValue)-\(settings.finish.rawValue)-\(state.rawValue)-\(size)-\(displayScale)") {
            let kind = resolvedKind, finish = settings.finish, state = state, framing = framing
            let size = CGSize(width: size, height: size), scale = max(displayScale, 1), t = moment
            let rendered = await Task.detached(priority: .userInitiated) {
                // No glow: on black it reads as a grey box around the character.
                CharacterRenderer.shared.snapshot(kind: kind, state: state, finish: finish, framing: framing,
                                                  sizePt: size, scale: scale, t: t, aura: false)
            }.value
            withAnimation(.easeOut(duration: 0.15)) { image = rendered }
        }
        .accessibilityHidden(true)
    }
}
