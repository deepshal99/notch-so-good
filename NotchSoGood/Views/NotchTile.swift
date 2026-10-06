import SwiftUI

/// A character in a little square of screen with a sliver of notch to hang
/// from — the app's icon-sized portrait, used in settings and the popover.
struct NotchTile: View {
    let state: CharacterState
    var kind: CharacterKind? = nil
    let size: CGFloat
    var radius: CGFloat = 12
    var framing: CharacterFraming = .tile

    var body: some View {
        CharacterView(state: state, framing: framing, kind: kind, framesPerSecond: 30)
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
