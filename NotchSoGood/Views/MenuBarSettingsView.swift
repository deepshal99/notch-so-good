import SwiftUI
import Sparkle

struct MenuBarSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    let updater: SPUUpdater

    @State private var axTrusted = AXIsProcessTrusted()

    private let bg = Color(hex: "0E0E0E")
    private let cardBg = Color.white.opacity(0.04)
    private let dim = Color.white.opacity(0.3)
    private let body_ = Color.white.opacity(0.78)
    private let sep = Color.white.opacity(0.06)

    var body: some View {
        VStack(spacing: 0) {
            // === HEADER ===
            VStack(spacing: 6) {
                MascotView(expression: .waving)
                    .scaleEffect(0.55)
                    .frame(width: 30, height: 26)

                Text("Notch So Good")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 14)

            // === SETTINGS ===
            VStack(spacing: 0) {
                toggleRow(icon: "checkmark.circle", label: "Complete", isOn: $notificationManager.showOnComplete)
                insetSep
                toggleRow(icon: "questionmark.circle", label: "Questions", isOn: $notificationManager.showOnQuestion)
                insetSep
                toggleRow(icon: "lock.circle", label: "Permissions", isOn: $notificationManager.showOnPermission)
                insetSep
                toggleRow(icon: "speaker.wave.2", label: "Sounds", isOn: $notificationManager.soundEnabled)
                insetSep
                toggleRow(icon: "capsule", label: "Session Pill", isOn: $notificationManager.showSessionPill)
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 10)

            // === ACCESSIBILITY HINT (re-checks every time menu opens) ===
            if !axTrusted {
                AccessibilityHintButton {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            Spacer().frame(height: 10)

            // === FOOTER ===
            Rectangle().fill(sep).frame(height: 0.5).padding(.horizontal, 14)

            Spacer().frame(height: 2)

            footerRow(icon: "arrow.triangle.2.circlepath", label: "Update", trailing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") {
                updater.checkForUpdates()
            }

            footerRow(icon: "terminal", label: "Reinstall Hooks", trailing: "Claude + Codex") {
                notificationManager.installHooks()
            }

            footerRow(icon: "power", label: "Quit", trailing: "\u{2318}Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")

            // === CREDIT ===
            Button {
                if let url = URL(string: "https://x.com/deepshal99") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("made by Deepak")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CreditButtonStyle())
        }
        .frame(width: 240)
        .background(bg)
        .preferredColorScheme(.dark)
        .onAppear { axTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Inset Separator

    private var insetSep: some View {
        Rectangle().fill(sep).frame(height: 0.5).padding(.leading, 36)
    }

    // MARK: - Toggle Row

    private func toggleRow(
        icon: String,
        label: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(dim)
                .frame(width: 16, alignment: .center)

            Text(label)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(body_)

            Spacer()

            MinimalToggle(isOn: isOn)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Footer Row

    private func footerRow(
        icon: String,
        label: String,
        trailing: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(dim)
                    .frame(width: 16, alignment: .center)

                Text(label)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundColor(body_)

                Spacer()

                Text(trailing)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

// MARK: - Button Styles

private struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(isHovered ? 0.05 : 0))
                    .padding(.horizontal, 4)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { h in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
            }
    }
}

// MARK: - Minimal Toggle

private struct MinimalToggle: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 28
    private let trackHeight: CGFloat = 16
    private let thumbSize: CGFloat = 12
    private let thumbPadding: CGFloat = 2

    var body: some View {
        let onColor = Color.white.opacity(0.9)
        let offTrack = Color.white.opacity(0.1)
        let onTrack = Color.white.opacity(0.25)

        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? onTrack : offTrack)
                    .frame(width: trackWidth, height: trackHeight)

                Circle()
                    .fill(isOn ? onColor : Color.white.opacity(0.35))
                    .frame(width: thumbSize, height: thumbSize)
                    .padding(.horizontal, thumbPadding)
            }
        }
        .buttonStyle(.plain)
        .frame(width: trackWidth, height: trackHeight)
    }
}

// MARK: - Accessibility Hint Button

private struct AccessibilityHintButton: View {
    let action: () -> Void
    @State private var isHovered = false

    private let orangeTint = Color.orange

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grant Accessibility Access")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.8))
                    Text("For precise window targeting")
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(orangeTint.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(orangeTint.opacity(isHovered ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(orangeTint.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.0 : 1.0)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
        }
    }
}

private struct CreditButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isHovered ? 0.8 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { h in isHovered = h }
    }
}
