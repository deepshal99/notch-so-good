import SwiftUI

struct SpeechBubbleView: View {
    let message: String
    let title: String
    let type: NotificationType
    @Binding var isVisible: Bool
    @Binding var textRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title with icon
            HStack(spacing: 5) {
                Image(systemName: type.sfSymbol)
                    .foregroundColor(type.accentColor)
                    .font(.system(size: 10, weight: .semibold))

                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .opacity(textRevealed ? 1 : 0)

            // Message
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
                .lineSpacing(1)
                .opacity(textRevealed ? 1 : 0)
        }
        .scaleEffect(isVisible ? 1 : 0.5, anchor: .leading)
        .opacity(isVisible ? 1 : 0)
    }
}
