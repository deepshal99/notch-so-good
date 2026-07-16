import SwiftUI
import Sparkle
import ServiceManagement

struct MenuBarSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject private var statsStore = StatsStore.shared
    let updater: SPUUpdater

    @State private var axTrusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let bg = Color(hex: "0E0E0E")
    private let cardBg = Color.white.opacity(0.04)
    private let dim = Color.white.opacity(0.3)
    private let body_ = Color.white.opacity(0.78)
    private let sep = Color.white.opacity(0.06)

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = enable
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            statTiles
                .padding(.horizontal, 12)

            sectionHeader("NOTIFICATIONS")

            LazyVGrid(columns: columns, spacing: 8) {
                toggleChip(icon: "checkmark.circle", label: "Complete", isOn: $notificationManager.showOnComplete)
                toggleChip(icon: "questionmark.circle", label: "Questions", isOn: $notificationManager.showOnQuestion)
                toggleChip(icon: "lock.circle", label: "Permissions", isOn: $notificationManager.showOnPermission)
                toggleChip(icon: "speaker.wave.2", label: "Sounds", isOn: $notificationManager.soundEnabled)
            }
            .padding(.horizontal, 12)

            sectionHeader("BEHAVIOR")

            LazyVGrid(columns: columns, spacing: 8) {
                toggleChip(icon: "capsule", label: "Session Pill", isOn: $notificationManager.showSessionPill)
                toggleChip(icon: "bell.badge", label: "Nudge", isOn: $notificationManager.nudgeEnabled)
                toggleChip(icon: "play.circle", label: "Login Item", isOn: launchAtLoginBinding)
                toggleChip(icon: "chart.bar", label: "Anon Stats", isOn: $notificationManager.telemetryEnabled)
            }
            .padding(.horizontal, 12)

            if !notificationManager.history.isEmpty {
                sectionHeader("RECENT")

                VStack(spacing: 0) {
                    let items = Array(notificationManager.history.prefix(4))
                    ForEach(items) { item in
                        historyRow(item)
                        if item.id != items.last?.id {
                            Rectangle().fill(sep).frame(height: 0.5).padding(.leading, 34)
                        }
                    }
                }
                .background(cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
            }

            if !axTrusted {
                AccessibilityHintButton {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            // === FOOTER ===
            HStack(spacing: 8) {
                footerChip(icon: "arrow.triangle.2.circlepath", label: "Update") {
                    updater.checkForUpdates()
                }
                footerChip(icon: "terminal", label: "Hooks") {
                    notificationManager.installHooks()
                }
                footerChip(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // === CREDIT ===
            Button {
                if let url = URL(string: "https://x.com/deepshal99") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("made by Deepak")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CreditButtonStyle())
        }
        .frame(width: 320)
        .background(bg)
        .preferredColorScheme(.dark)
        .onAppear {
            axTrusted = AXIsProcessTrusted()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            MascotView(expression: .waving)
                .scaleEffect(0.5)
                .frame(width: 28, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("Notch So Good")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("watching your agents")
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundColor(dim)
            }

            Spacer()

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(dim)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.05)))
        }
    }

    // MARK: - Stat tiles ("Chawd's shift report")

    private var statTiles: some View {
        let stats = statsStore.today
        return HStack(spacing: 8) {
            statTile(value: "\(stats.sessionsStarted)", caption: "SESSIONS")
            statTile(value: "\(stats.tasksCompleted)", caption: "DONE")
            statTile(value: StatsStore.formatDuration(stats.activeSeconds), caption: "ACTIVE")
        }
    }

    private func statTile(value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(dim)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Toggle chip (whole chip is the click target)

    private func toggleChip(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isOn.wrappedValue ? .white.opacity(0.65) : dim)
                    .frame(width: 14, alignment: .center)

                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(body_)
                    .lineLimit(1)

                Spacer(minLength: 2)

                TogglePill(isOn: isOn.wrappedValue)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(ChipButtonStyle())
    }

    // MARK: - History Row

    private func historyRow(_ item: NotchNotification) -> some View {
        Button {
            TerminalLauncher.focusClaudeCode(sessionId: item.sessionId, sourceBundleId: item.sourceBundleId)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.type.sfSymbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(item.type.accentColor.opacity(0.8))
                    .frame(width: 16, alignment: .center)

                Text(item.message)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(body_)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(relativeTime(item.timestamp))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
    }

    // MARK: - Footer chip

    private func footerChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(dim)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(body_)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(ChipButtonStyle())
    }
}

// MARK: - Button Styles

private struct ChipButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.04 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { h in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
            }
    }
}

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

// MARK: - Toggle pill (pure visual — the chip handles interaction)

private struct TogglePill: View {
    let isOn: Bool

    private let trackWidth: CGFloat = 26
    private let trackHeight: CGFloat = 15
    private let thumbSize: CGFloat = 11
    private let thumbPadding: CGFloat = 2

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                .frame(width: trackWidth, height: trackHeight)

            Circle()
                .fill(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                .frame(width: thumbSize, height: thumbSize)
                .padding(.horizontal, thumbPadding)
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(.easeOut(duration: 0.15), value: isOn)
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
