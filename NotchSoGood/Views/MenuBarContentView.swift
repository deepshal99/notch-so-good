import SwiftUI
import Combine

/// The menu bar menu. Built like a system menu (Wi-Fi, Battery): the window's
/// own material, the system type scale, inset separators, rows that highlight
/// like menu items. It answers two questions — how much runway is left, and
/// what are my agents doing — and gets out of the way. Settings live in their
/// own window.
struct MenuBarContentView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject private var limits = UsageLimitsStore.shared
    @ObservedObject private var characterSettings = CharacterSettings.shared
    @Environment(\.openSettings) private var openSettings

    @State private var axTrusted = AXIsProcessTrusted()
    private let axRecheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            MenuSeparator()
            usage

            if !notificationManager.activeSessions.isEmpty {
                MenuSeparator()
                sessions
            }

            if !axTrusted {
                MenuSeparator()
                MenuRow(action: openAccessibilitySettings) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Allow Accessibility Access…")
                        Text("Lets a click jump to the exact terminal window")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MenuSeparator()
            MenuRow(action: showSettings) {
                Text("Settings…")
                Spacer()
                Text("⌘,").foregroundStyle(.secondary)
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit Notch So Good")
                Spacer()
                Text("⌘Q").foregroundStyle(.secondary)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.system(size: 13))
        .padding(.vertical, 5)
        .frame(width: 296)
        // Always the island's dark surface. Following the system glass made the
        // menu grey-on-grey in Light mode over dark windows.
        .background(MenuMetrics.surface)
        .environment(\.colorScheme, .dark)
        .onAppear {
            axTrusted = AXIsProcessTrusted()
            limits.refresh(force: true)
        }
        .onReceive(axRecheck) { _ in axTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            NotchTile(state: headerState, size: 32, radius: 8, framing: .portrait, live: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("Notch So Good")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MenuMetrics.inset)
        .padding(.top, 7)
        .padding(.bottom, 9)
    }

    private var headerState: CharacterState {
        let sessions = notificationManager.activeSessions
        if sessions.contains(where: { $0.status == .needsInput || $0.status == .needsPermission }) { return .need }
        return sessions.isEmpty ? .idle : .work
    }

    private var statusLine: String {
        let sessions = notificationManager.activeSessions
        if sessions.isEmpty { return "\(characterSettings.kind.displayName) is off duty" }
        let waiting = sessions.filter { $0.status == .needsInput || $0.status == .needsPermission }.count
        if waiting > 0 { return "\(waiting) waiting on you" }
        return "\(sessions.count) session\(sessions.count == 1 ? "" : "s") working"
    }

    // MARK: - Usage

    @ViewBuilder
    private var usage: some View {
        let windows = limits.windows
        if windows.isEmpty {
            MenuSectionHeader("Usage")
            switch limits.status {
            case .loading:
                MenuNote("Checking…")
            case .signedOut:
                MenuNote("Run /login in Claude Code to see your limits.")
            case .unavailable, .ready:
                MenuRow(action: { limits.refresh(force: true) }) {
                    Text("Couldn't load usage")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Retry")
                }
            }
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(agents(windows), id: \.self) { agent in
                        MenuSectionHeader(agent == .claude ? "Claude Code" : agent.displayName)
                            .padding(.top, agent == agents(windows).first ? 0 : 6)
                        ForEach(windows.filter { $0.source == agent }) { window in
                            UsageMeterRow(window: window, now: context.date)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func agents(_ windows: [UsageLimitsStore.LimitWindow]) -> [AgentSource] {
        var seen: [AgentSource] = []
        for w in windows where !seen.contains(w.source) { seen.append(w.source) }
        return seen
    }

    // MARK: - Sessions

    private var sessions: some View {
        let all = notificationManager.orderedSessions
        return VStack(alignment: .leading, spacing: 0) {
            MenuSectionHeader("Sessions")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    ForEach(all.prefix(6)) { session in
                        sessionRow(session, now: context.date)
                    }
                }
            }
            if all.count > 6 {
                MenuNote("\(all.count - 6) more in the notch")
            }
        }
    }

    private func sessionRow(_ session: NotificationManager.SessionInfo, now: Date) -> some View {
        let waiting = session.status == .needsInput || session.status == .needsPermission
        return MenuRow(action: {
            TerminalLauncher.focusClaudeCode(sessionId: session.id, sourceBundleId: session.sourceBundleId,
                                             cwd: session.cwd, sourcePid: session.sourcePid)
        }) {
            Circle()
                .fill(session.status.dotColor)
                .frame(width: 7, height: 7)
            Text(session.projectName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(session.status.activityLine(toolName: session.activeToolName, toolDetail: nil))
                .foregroundStyle(waiting ? AnyShapeStyle(session.status.dotColor) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .fixedSize()
            Text(ElapsedFormatter.clock(Int(now.timeIntervalSince(session.startTime))))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .help("Open in terminal")
    }

    // MARK: - Actions

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Usage meter

/// "5-hour  ━━━━━━━━──────  60%", with when it resets (or, if the current pace
/// won't last, when it runs out) underneath.
private struct UsageMeterRow: View {
    let window: UsageLimitsStore.LimitWindow
    let now: Date

    private var name: String {
        if window.label == "Session" { return "5-hour" }
        if let r = window.label.range(of: "Weekly · ") { return "Weekly (\(window.label[r.upperBound...]))" }
        return window.label
    }

    private var tint: Color {
        if window.percentLeft < 10 { return .red }
        if window.percentLeft < 25 { return .orange }
        return .accentColor
    }

    private var runsOut: Date? {
        guard let resetsAt = window.resetsAt, let length = UsageForecast.windowLength(label: window.label),
              case .runsOut(let date)? = UsageForecast.outcome(percentLeft: window.percentLeft, resetsAt: resetsAt,
                                                                windowLength: length, now: now)
        else { return nil }
        return date
    }

    var body: some View {
        let fraction = CGFloat(min(100, max(0, window.percentLeft))) / 100
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .lineLimit(1)
                    .layoutPriority(1)
                caption
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(window.percentLeft)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(tint).frame(width: max(5, g.size.width*fraction))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, MenuMetrics.inset)
        .padding(.vertical, 6)
        .help(window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var caption: some View {
        if let runsOut {
            Text("runs out \(Self.when(runsOut, now: now))")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .help("At the pace so far this window, it runs out before it resets.")
        } else if let resetsAt = window.resetsAt {
            Text("resets in \(UsageLimitsStore.resetCountdown(resetsAt))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    /// "at 3:40 PM" today, "Fri 10:21 AM" otherwise.
    static func when(_ date: Date, now: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "at \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

// MARK: - Menu building blocks

private enum MenuMetrics {
    /// Text inset from the window edge, as in system menus.
    static let inset: CGFloat = 14
    /// Near-black, a step up from the notch so the menu reads as a surface.
    static let surface = Color(red: 0.086, green: 0.086, blue: 0.094)
}

private struct MenuSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 5)
    }
}

private struct MenuSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.top, 4)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct MenuNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 4)
    }
}

/// A clickable row that highlights like a menu item: a rounded selection
/// inset from the window edge, text aligned to the menu's inset.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, MenuMetrics.inset - 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .onHover { hovered = $0 }
    }
}
