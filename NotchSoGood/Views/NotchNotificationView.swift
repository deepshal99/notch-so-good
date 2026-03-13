import SwiftUI

struct NotchNotificationView: View {
    let notification: NotchNotification
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var expanded = false
    @State private var contentAppeared = false
    @State private var textRevealed = false
    @State private var glowVisible = false
    @State private var glowRotation: Double = 0

    private let bottomRadius: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let fullHeight = geo.size.height

            // Scale factors: start at notch size, expand to full
            let startScaleX = hasNotch ? (notchWidth + 8) / fullWidth : 0.5
            let startScaleY = hasNotch ? (notchHeight + 4) / fullHeight : 0.15

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // === ANIMATED GRADIENT GLOW (behind the shape) ===
                    if glowVisible {
                        glowBorder(width: fullWidth, height: fullHeight)
                    }

                    // === MAIN BACKGROUND — always full size, scaled ===
                    islandShape
                        .fill(Color.black)
                        .contentShape(islandShape)

                    // === CONTENT ===
                    contentView
                        .padding(.top, hasNotch ? notchHeight + 10 : 12)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .allowsHitTesting(false)
                }
                .frame(width: fullWidth, height: fullHeight)
                .scaleEffect(
                    x: expanded ? 1 : startScaleX,
                    y: expanded ? 1 : startScaleY,
                    anchor: .top
                )
                .contentShape(islandShape)
                .onTapGesture(perform: onTap)
            }
            .frame(width: fullWidth, height: fullHeight, alignment: .top)
        }
        .onAppear(perform: animateIn)
    }

    // MARK: - Animated gradient glow around the border

    private func glowBorder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Layer 1: Wider, softer outer glow
            islandShape
                .stroke(
                    AngularGradient(
                        colors: [
                            notification.type.accentColor.opacity(0.0),
                            notification.type.accentColor.opacity(0.15),
                            notification.type.accentColor.opacity(0.0),
                            notification.type.accentColor.opacity(0.08),
                            notification.type.accentColor.opacity(0.0),
                        ],
                        center: .center,
                        startAngle: .degrees(glowRotation),
                        endAngle: .degrees(glowRotation + 360)
                    ),
                    lineWidth: 6
                )
                .blur(radius: 8)
                .opacity(textRevealed ? 1 : 0)

            // Layer 2: Tighter, brighter inner glow
            islandShape
                .stroke(
                    AngularGradient(
                        colors: [
                            notification.type.accentColor.opacity(0.0),
                            notification.type.accentColor.opacity(0.25),
                            notification.type.accentColor.opacity(0.0),
                            notification.type.accentColor.opacity(0.0),
                        ],
                        center: .center,
                        startAngle: .degrees(glowRotation + 180),
                        endAngle: .degrees(glowRotation + 540)
                    ),
                    lineWidth: 2
                )
                .blur(radius: 3)
                .opacity(textRevealed ? 1 : 0)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                glowRotation = 360
            }
        }
    }

    // Reusable shape
    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - Content

    private var contentView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(notification.type.accentColor.opacity(0.08))
                    .frame(width: 52, height: 52)

                MascotView(expression: notification.type.mascotExpression)
                    .frame(width: 50, height: 46)
            }
            .opacity(contentAppeared ? 1 : 0)
            .scaleEffect(contentAppeared ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: notification.type.sfSymbol)
                        .foregroundColor(notification.type.accentColor)
                        .font(.system(size: 9, weight: .bold))

                    Text(notification.displayTitle.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(notification.type.accentColor.opacity(0.8))
                        .tracking(0.8)
                }
                .opacity(textRevealed ? 1 : 0)

                Text(notification.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .opacity(textRevealed ? 1 : 0)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Animation

    private func animateIn() {
        // 1. Shape expands from notch size (scale preserves corner radius)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            expanded = true
        }
        // 2. Mascot pops in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                contentAppeared = true
            }
            glowVisible = true
        }
        // 3. Text fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                textRevealed = true
            }
        }
    }
}
