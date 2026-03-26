import SwiftUI

/// Animated phase icon that shows the current session state.
/// Replaces plain color dots with expressive, tool-aware SF Symbols.
struct PhaseIconView: View {
    let status: SessionStatus
    var toolName: String? = nil
    var size: CGFloat = 12
    var compact: Bool = false  // smaller for collapsed pill / subagent rows

    @State private var isAnimating = false
    @State private var spinAngle: Double = 0

    private var icon: String {
        if status == .running, let tool = toolName {
            return SessionStatus.toolIcon(tool)
        }
        return status.phaseIcon
    }

    private var color: Color {
        status.dotColor
    }

    private var iconSize: CGFloat {
        compact ? size * 0.7 : size
    }

    var body: some View {
        ZStack {
            // Subtle glow behind icon for active states (contained within frame)
            if status.shouldPulse {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: size, height: size)
                    .blur(radius: 3)
            }

            // The icon itself
            Group {
                switch status {
                case .running:
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(color)
                        .scaleEffect(isAnimating ? 1.05 : 0.95)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: isAnimating
                        )

                case .needsInput:
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(color)
                        .offset(y: isAnimating ? -0.5 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: isAnimating
                        )

                case .needsPermission:
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(color)
                        .rotationEffect(.degrees(isAnimating ? 2 : -2))
                        .animation(
                            .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                            value: isAnimating
                        )

                case .compacting:
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(color)
                        .rotationEffect(.degrees(spinAngle))
                        .animation(
                            .linear(duration: 2.0).repeatForever(autoreverses: false),
                            value: spinAngle
                        )

                case .completed:
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(color)
                }
            }
        }
        .frame(width: size + 2, height: size + 2)
        .clipped()
        .onAppear {
            isAnimating = true
            if status == .compacting {
                spinAngle = 360
            }
        }
    }
}

// MARK: - Subagent count badge

struct SubagentBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 7, weight: .bold))
            Text("\(count)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.5))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(.white.opacity(0.08))
        )
    }
}
