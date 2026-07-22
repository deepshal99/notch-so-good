import SwiftUI
import Sparkle
import ServiceManagement

/// Control Center-style popover: identity header with icon actions, content-first
/// cards (limits, today, active session), settings tucked behind the gear.
struct MenuBarSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject private var statsStore = StatsStore.shared
    @ObservedObject private var limitsStore = UsageLimitsStore.shared
    let updater: SPUUpdater

    @State private var showSettings = false
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let axRecheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private let bg = Color(hex: "0E0E0E")
    private let cardBg = Color.white.opacity(0.06)
    private let dim = Color.white.opacity(0.38)
    private let body_ = Color.white.opacity(0.92)
    private let sep = Color.white.opacity(0.06)

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
        VStack(spacing: 12) {
            if showSettings {
                settingsPane
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                mainPane
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            credit
        }
        .padding(14)
        .frame(width: 336)
        .background(bg)
        .preferredColorScheme(.dark)
        .animation(.smooth, value: showSettings)
        .onAppear {
            axTrusted = AXIsProcessTrusted()
            launchAtLogin = SMAppService.mainApp.status == .enabled
            UsageLimitsStore.shared.refresh(force: true)
        }
        .onReceive(axRecheck) { _ in
            axTrusted = AXIsProcessTrusted()
        }
    }

    // MARK: - Main pane

    private var mainPane: some View {
        VStack(spacing: 12) {
            headerCard

            if !limitsStore.windows.isEmpty {
                limitsCard
            }

            todayTiles

            if !notificationManager.activeSessions.isEmpty {
                activeSessionsCard
            }

            if !notificationManager.history.isEmpty {
                recentCard
            }

            if !axTrusted {
                AccessibilityHintButton {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 38, height: 38)
                MascotView(expression: .waving)
                    .scaleEffect(0.45)
                    .frame(width: 30, height: 26)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Notch So Good")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(statusLine)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(dim)
            }

            Spacer()

            // Joined icon actions, Control Center style
            HStack(spacing: 0) {
                headerIconButton(icon: "gearshape.fill") {
                    showSettings = true
                }
                Rectangle().fill(sep).frame(width: 0.5, height: 16)
                headerIconButton(icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(14)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusLine: String {
        let sessions = notificationManager.activeSessions
        if sessions.isEmpty { return "all quiet — Chawd is off duty" }
        let waiting = sessions.filter { $0.status == .needsInput || $0.status == .needsPermission }.count
        if waiting > 0 { return "\(waiting) session\(waiting == 1 ? "" : "s") waiting on you" }
        return "\(sessions.count) session\(sessions.count == 1 ? "" : "s") active"
    }

    private func headerIconButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HeaderIconButtonStyle())
    }

    // MARK: - Limits card

    private var limitsCard: some View {
        VStack(spacing: 0) {
            let windows = limitsStore.windows
            ForEach(windows) { window in
                limitRow(window)
                if window.id != windows.last?.id {
                    Rectangle().fill(sep).frame(height: 0.5).padding(.horizontal, 14)
                }
            }
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func limitRow(_ window: UsageLimitsStore.LimitWindow) -> some View {
        let color = limitColor(window.percentLeft)
        let showAgent = Set(limitsStore.windows.map { $0.source }).count > 1

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if showAgent {
                    Circle()
                        .fill(window.source.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(y: -1)
                }
                Text(showAgent ? "\(window.source.displayName) · \(window.label)" : window.label)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(body_)

                Spacer()

                Text("\(window.percentLeft)% left")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(color)
                        .frame(width: max(6, geo.size.width * CGFloat(window.percentLeft) / 100))
                }
            }
            .frame(height: 6)

            if let resetsAt = window.resetsAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("Resets in \(UsageLimitsStore.resetCountdown(resetsAt))")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                }
                .foregroundColor(dim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func limitColor(_ percentLeft: Int) -> Color {
        if percentLeft <= 10 { return Color(hex: "F87171") }
        if percentLeft <= 25 { return Color(hex: "FBBF24") }
        return Color(hex: "369EFF")
    }

    // MARK: - Today tiles

    private var todayTiles: some View {
        let stats = statsStore.today
        return HStack(spacing: 12) {
            todayTile(icon: "play.fill", color: Color(hex: "60A5FA"),
                      value: "\(stats.sessionsStarted)", caption: "SESSIONS")
            todayTile(icon: "checkmark", color: Color(hex: "34D399"),
                      value: "\(stats.tasksCompleted)", caption: "DONE")
            todayTile(icon: "clock.fill", color: Color(hex: "FBBF24"),
                      value: StatsStore.formatDuration(stats.activeSeconds), caption: "ACTIVE")
        }
    }

    private func todayTile(icon: String, color: Color, value: String, caption: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundColor(dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Active sessions card ("now playing")

    private var activeSessionsCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                let sessions = Array(notificationManager.activeSessions.prefix(3))
                ForEach(sessions) { session in
                    sessionRow(session, now: context.date)
                    if session.id != sessions.last?.id {
                        Rectangle().fill(sep).frame(height: 0.5).padding(.horizontal, 14)
                    }
                }
                if notificationManager.activeSessions.count > 3 {
                    Text("+\(notificationManager.activeSessions.count - 3) more")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 44)
                        .padding(.bottom, 7)
                }
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func sessionRow(_ session: NotificationManager.SessionInfo, now: Date) -> some View {
        Button {
            TerminalLauncher.focusClaudeCode(sessionId: session.id, sourceBundleId: session.sourceBundleId, cwd: session.cwd)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(session.status.dotColor.opacity(0.15))
                        .frame(width: 26, height: 26)
                    PhaseIconView(status: session.status, toolName: session.activeToolName, size: 10, compact: true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(body_)
                        .lineLimit(1)
                    Text(session.status.phaseLabel(toolName: session.activeToolName, toolDetail: session.activeToolDetail))
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(session.status.dotColor.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(elapsed(since: session.startTime, now: now))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.06)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        if secs < 3600 { return String(format: "%d:%02d", secs / 60, secs % 60) }
        return String(format: "%d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60)
    }

    // MARK: - Recent card

    private var recentCard: some View {
        VStack(spacing: 0) {
            let items = Array(notificationManager.history.prefix(3))
            ForEach(items) { item in
                historyRow(item)
                if item.id != items.last?.id {
                    Rectangle().fill(sep).frame(height: 0.5).padding(.horizontal, 14)
                }
            }
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

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
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(relativeTime(item.timestamp))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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

    // MARK: - Settings pane

    private var settingsPane: some View {
        VStack(spacing: 12) {
            // Back header
            HStack(spacing: 8) {
                Button {
                    showSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("Back")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(HeaderIconButtonStyle())

                Spacer()

                Text("Settings")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // Balance the back button so the title optically centers
                Color.clear.frame(width: 58, height: 1)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                settingRow(icon: "checkmark.circle", label: "Complete notifications", isOn: $notificationManager.showOnComplete)
                insetSep
                settingRow(icon: "questionmark.circle", label: "Question notifications", isOn: $notificationManager.showOnQuestion)
                insetSep
                settingRow(icon: "lock.circle", label: "Permission approvals", isOn: $notificationManager.showOnPermission)
                insetSep
                settingRow(icon: "speaker.wave.2", label: "Sounds", isOn: $notificationManager.soundEnabled)
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 0) {
                settingRow(icon: "capsule", label: "Session pill", isOn: $notificationManager.showSessionPill)
                insetSep
                settingRow(icon: "bell.badge", label: "Nudge when waiting", isOn: $notificationManager.nudgeEnabled)
                insetSep
                settingRow(icon: "play.circle", label: "Launch at login", isOn: launchAtLoginBinding)
                insetSep
                settingRow(icon: "chart.bar", label: "Anonymous stats", isOn: $notificationManager.telemetryEnabled)
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 0) {
                actionRow(icon: "arrow.triangle.2.circlepath", label: "Check for updates",
                          trailing: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")") {
                    updater.checkForUpdates()
                }
                insetSep
                actionRow(icon: "terminal", label: "Reinstall hooks", trailing: "Claude + Codex") {
                    notificationManager.installHooks()
                }
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var insetSep: some View {
        Rectangle().fill(sep).frame(height: 0.5).padding(.horizontal, 14)
    }

    private func settingRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn.wrappedValue ? .white.opacity(0.65) : dim)
                    .frame(width: 18, alignment: .center)

                Text(label)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(body_)

                Spacer()

                TogglePill(isOn: isOn.wrappedValue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    private func actionRow(icon: String, label: String, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(dim)
                    .frame(width: 18, alignment: .center)

                Text(label)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(body_)

                Spacer()

                Text(trailing)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    // MARK: - Credit

    private var credit: some View {
        Button {
            if let url = URL(string: "https://x.com/deepshal99") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("made by Deepak Maurya")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(CreditButtonStyle())
    }
}

// MARK: - Button styles

private struct HeaderIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : (isHovered ? 1.0 : 0.8))
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { h in
                withAnimation(.hover) { isHovered = h }
            }
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.05 : 0))
                    .padding(3)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { h in
                withAnimation(.hover) { isHovered = h }
            }
    }
}

// MARK: - Toggle pill (pure visual — the row handles interaction)

private struct TogglePill: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                .frame(width: 26, height: 15)

            Circle()
                .fill(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                .frame(width: 11, height: 11)
                .padding(.horizontal, 2)
        }
        .frame(width: 26, height: 15)
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
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(orangeTint.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(orangeTint.opacity(isHovered ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(orangeTint.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.hover) { isHovered = h }
        }
    }
}

private struct CreditButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isHovered ? 0.85 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.hover, value: isHovered)
            .onHover { h in isHovered = h }
    }
}
