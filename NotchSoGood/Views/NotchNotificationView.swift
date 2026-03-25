import SwiftUI

struct NotchNotificationView: View {
    let notification: NotchNotification
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: () -> Void
    let onDismiss: () -> Void
    let onApprove: (() -> Void)?
    let onDeny: (() -> Void)?

    @State private var expanded = false
    @State private var contentAppeared = false
    @State private var textRevealed = false
    @State private var glowVisible = false
    @State private var glowRotation: Double = 0
    @State private var buttonsRevealed = false

    private let bottomRadius: CGFloat = 26

    private var isPermission: Bool { notification.isInteractivePermission }

    init(
        notification: NotchNotification,
        hasNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        onTap: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onApprove: (() -> Void)? = nil,
        onDeny: (() -> Void)? = nil
    ) {
        self.notification = notification
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.onTap = onTap
        self.onDismiss = onDismiss
        self.onApprove = onApprove
        self.onDeny = onDeny
    }

    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let fullHeight = geo.size.height

            let startScaleX = hasNotch ? (notchWidth + 8) / fullWidth : 0.5
            let startScaleY = hasNotch ? (notchHeight + 4) / fullHeight : 0.15

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // === ANIMATED GRADIENT GLOW ===
                    if glowVisible {
                        glowBorder(width: fullWidth, height: fullHeight)
                    }

                    // === BACKGROUND ===
                    islandShape
                        .fill(Color.black)
                        .contentShape(islandShape)

                    // === CONTENT ===
                    VStack(spacing: 0) {
                        // Info row (non-interactive)
                        infoContent
                            .allowsHitTesting(false)

                        // Approve/Deny buttons (interactive, permission only)
                        if isPermission {
                            permissionButtons
                                .padding(.top, 10)
                                .opacity(buttonsRevealed ? 1 : 0)
                                .offset(y: buttonsRevealed ? 0 : 6)
                        }
                    }
                    .padding(.top, hasNotch ? notchHeight + 10 : 12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, isPermission ? 18 : 16)
                }
                .frame(width: fullWidth, height: fullHeight)
                .scaleEffect(
                    x: expanded ? 1 : startScaleX,
                    y: expanded ? 1 : startScaleY,
                    anchor: .top
                )
                .contentShape(islandShape)
                .onTapGesture {
                    if !isPermission { onTap() }
                }
            }
            .frame(width: fullWidth, height: fullHeight, alignment: .top)
        }
        .onAppear(perform: animateIn)
    }

    // MARK: - Glow

    private var glowShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius + 4,
            bottomTrailingRadius: bottomRadius + 4,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private func glowBorder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            glowShape
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
                .blur(radius: 10)
                .opacity(textRevealed ? 1 : 0)

            glowShape
                .stroke(
                    AngularGradient(
                        colors: [
                            notification.type.accentColor.opacity(0.0),
                            notification.type.accentColor.opacity(0.2),
                            notification.type.accentColor.opacity(0.0),
                            notification.type.accentColor.opacity(0.0),
                        ],
                        center: .center,
                        startAngle: .degrees(glowRotation + 180),
                        endAngle: .degrees(glowRotation + 540)
                    ),
                    lineWidth: 2
                )
                .blur(radius: 4)
                .opacity(textRevealed ? 1 : 0)
        }
        .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: glowRotation)
        .onAppear {
            glowRotation = 360
        }
    }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - Info content

    private var infoContent: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(notification.type.accentColor.opacity(0.08))
                    .frame(width: 52, height: 52)

                MascotView(expression: notification.type.mascotExpression)
                    .frame(width: 50, height: 46)
            }
            .opacity(contentAppeared ? 1 : 0)
            .scaleEffect(contentAppeared ? 1 : 0.85)

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

                if isPermission, let tool = notification.toolName {
                    // Tool name badge
                    HStack(spacing: 4) {
                        Image(systemName: toolIcon(for: tool))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(notification.type.accentColor.opacity(0.6))
                        Text(tool)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .opacity(textRevealed ? 1 : 0)
                }

                Text(notification.message)
                    .font(.system(size: isPermission ? 12 : 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(isPermission ? 2 : 2)
                    .lineSpacing(2)
                    .opacity(textRevealed ? 1 : 0)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Permission buttons

    private var permissionButtons: some View {
        HStack(spacing: 8) {
            PermissionButton(
                label: "Deny",
                icon: "xmark",
                style: .deny
            ) {
                onDeny?()
            }

            PermissionButton(
                label: "Allow",
                icon: "checkmark",
                style: .approve
            ) {
                onApprove?()
            }
        }
    }

    // MARK: - Helpers

    private func toolIcon(for tool: String) -> String {
        switch tool {
        case "Bash": return "terminal"
        case "Edit": return "pencil"
        case "Write": return "doc.badge.plus"
        case "NotebookEdit": return "doc.text"
        case "TaskCreate", "TaskUpdate", "TaskStop": return "checklist"
        case "WebFetch", "WebSearch": return "globe"
        case "SendMessage": return "paperplane"
        default: return "wrench"
        }
    }

    // MARK: - Animation

    private func animateIn() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            expanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                contentAppeared = true
            }
            glowVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                textRevealed = true
            }
        }
        // Staggered button reveal (permission only)
        if isPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    buttonsRevealed = true
                }
            }
        }
    }
}

// MARK: - Permission Button

private struct PermissionButton: View {
    enum Style { case approve, deny }

    let label: String
    let icon: String
    let style: Style
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private var bgColor: Color {
        switch style {
        case .approve: return Color(hex: "34D399") // emerald
        case .deny: return Color.white
        }
    }

    private var bgOpacity: Double {
        switch style {
        case .approve: return isHovered ? 0.3 : 0.2
        case .deny: return isHovered ? 0.1 : 0.06
        }
    }

    private var textColor: Color {
        switch style {
        case .approve: return .white
        case .deny: return .white.opacity(0.6)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bgColor.opacity(bgOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(bgColor.opacity(style == .approve ? 0.3 : 0.08), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { h in isHovered = h }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
