import SwiftUI

/// Animated phase icon that shows the current session state.
/// Replaces plain color dots with expressive, tool-aware SF Symbols.
///
/// The resting (un-animated) appearance is deliberately the *full-strength* one,
/// so honouring Reduce Motion never leaves the icon dimmed or shrunk.
struct PhaseIconView: View {
    let status: SessionStatus
    var toolName: String? = nil
    var size: CGFloat = 12
    var compact: Bool = false  // smaller for collapsed pill / subagent rows

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private func loop(_ duration: Double, autoreverses: Bool = true) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: duration).repeatForever(autoreverses: autoreverses)
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
                    symbol
                        .scaleEffect(isAnimating ? 1.06 : 1.0)
                        .animation(loop(0.8), value: isAnimating)

                case .needsInput:
                    symbol
                        .offset(y: isAnimating ? -1 : 0)
                        .opacity(isAnimating ? 0.7 : 1.0)
                        .scaleEffect(isAnimating ? 0.95 : 1.0)
                        .animation(loop(1.0), value: isAnimating)

                case .needsPermission:
                    symbol
                        .rotationEffect(.degrees(isAnimating ? 3 : 0))
                        .animation(loop(0.3), value: isAnimating)
                        // Slower, separate pulse layered under the quicker wobble
                        .opacity(isAnimating ? 0.7 : 1.0)
                        .scaleEffect(isAnimating ? 0.95 : 1.0)
                        .animation(loop(1.2), value: isAnimating)

                case .compacting:
                    symbol
                        .rotationEffect(.degrees(spinAngle))
                        .animation(
                            reduceMotion ? nil : .linear(duration: 2.0).repeatForever(autoreverses: false),
                            value: spinAngle
                        )

                case .completed:
                    symbol
                }
            }
        }
        .frame(width: size + 2, height: size + 2)
        .clipped()
        // The surrounding row already announces the phase in words.
        .accessibilityHidden(true)
        .onAppear { restart() }
        .onChange(of: status) { _, _ in restart() }
        .onChange(of: toolName) { _, _ in restart() }
        .onChange(of: reduceMotion) { _, _ in restart() }
    }

    private var symbol: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(color)
    }

    /// Repeating animations only attach on a false→true transition of their
    /// `value:`. `isAnimating` was previously set once in `onAppear` and never
    /// reset, so after the very first status change the icon swapped symbol and
    /// then sat completely frozen.
    private func restart() {
        isAnimating = false
        spinAngle = 0
        guard !reduceMotion else { return }
        DispatchQueue.main.async {
            isAnimating = true
            if status == .compacting { spinAngle = 360 }
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
        .accessibilityLabel("\(count) subagent\(count == 1 ? "" : "s") running")
    }
}
