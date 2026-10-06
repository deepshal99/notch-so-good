import SwiftUI
import Combine

/// The menu bar panel, in the island's language: who's working and how much
/// runway is left, then Settings and Quit. Dark whatever the system
/// appearance, like the notch it belongs to.
struct MenuBarContentView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject private var limits = UsageLimitsStore.shared
    @ObservedObject private var characterSettings = CharacterSettings.shared

    @Environment(\.dismiss) private var dismiss
    @State private var menuWindow: NSWindow?
    @State private var axTrusted = AXIsProcessTrusted()
    private let axRecheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !axTrusted { accessibilityCard }
            usage
            if !notificationManager.activeSessions.isEmpty { sessions }
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(Panel.background)
        .background(WindowReader { menuWindow = $0 })
        .environment(\.colorScheme, .dark)
        .onAppear {
            axTrusted = AXIsProcessTrusted()
            limits.refresh(force: true)
        }
        .onReceive(axRecheck) { _ in axTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            NotchTile(state: headerState, size: 38, radius: 10, framing: .portrait, live: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notch So Good")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Panel.primary)
                Text(statusLine)
                    .font(Panel.subtitle)
                    .foregroundColor(waitingCount > 0 ? CharacterState.need.color : Panel.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var waitingCount: Int {
        notificationManager.activeSessions.filter { $0.status == .needsInput || $0.status == .needsPermission }.count
    }

    private var headerState: CharacterState {
        if waitingCount > 0 { return .need }
        return notificationManager.activeSessions.isEmpty ? .idle : .work
    }

    private var statusLine: String {
        let sessions = notificationManager.activeSessions
        if sessions.isEmpty { return "\(characterSettings.kind.displayName) is off duty" }
        if waitingCount > 0 { return "\(waitingCount) waiting on you" }
        return "\(sessions.count) session\(sessions.count == 1 ? "" : "s") working"
    }

    // MARK: - Accessibility

    private var accessibilityCard: some View {
        PanelCard {
            PanelRow(icon: "hand.raised.fill", title: "Allow Accessibility",
                     subtitle: "So a click jumps to the exact terminal window.") {
                Button("Open") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PanelButtonStyle(kind: .outline))
            }
        }
    }

    // MARK: - Usage

    @ViewBuilder
    private var usage: some View {
        let windows = limits.windows
        if windows.isEmpty {
            PanelSection("Usage") {
                HStack(spacing: 12) {
                    Image(systemName: limits.status == .loading ? "clock" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Panel.icon)
                        .frame(width: Panel.iconColumn)
                    Text(placeholderText)
                        .font(Panel.subtitle)
                        .foregroundColor(Panel.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if limits.status != .loading {
                        Button("Retry") { limits.refresh(force: true) }
                            .buttonStyle(PanelButtonStyle(kind: .outline))
                    }
                }
                .padding(Panel.rowPadding)
            }
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(agents(windows), id: \.self) { agent in
                        PanelSection(agent == .claude ? "Claude Code" : agent.displayName) {
                            UsageStats(windows: windows.filter { $0.source == agent }, now: context.date)
                        }
                    }
                }
            }
        }
    }

    private var placeholderText: String {
        switch limits.status {
        case .loading: return "Checking your limits…"
        case .signedOut: return "Run /login in Claude Code to see your limits."
        case .unavailable, .ready: return "Couldn't reach the usage service."
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
        let shown = Array(all.prefix(5))
        return PanelSection("Sessions") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { PanelDivider(inset: Panel.rowPadding + 18) }
                        SessionMenuRow(session: session, now: context.date)
                    }
                    if all.count > shown.count {
                        PanelDivider(inset: Panel.rowPadding)
                        Text("\(all.count - shown.count) more in the notch")
                            .font(Panel.subtitle)
                            .foregroundColor(Panel.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Panel.rowPadding)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(PanelButtonStyle(kind: .quiet))
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit Notch So Good (⌘Q)")

            Spacer()

            Button {
                // Close the menu first; it otherwise floats over Settings.
                dismiss()
                menuWindow?.orderOut(nil)
                SettingsWindowController.shared.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .semibold))
                    Text("Settings")
                }
            }
            .buttonStyle(PanelButtonStyle(kind: .outline))
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
        }
    }
}

// MARK: - Usage stats

/// One agent's windows as stat columns: name, the number, a thin bar, and
/// when it resets. If the current pace won't last, one line says when it runs out.
private struct UsageStats: View {
    let windows: [UsageLimitsStore.LimitWindow]
    let now: Date

    var body: some View {
        let runout = firstRunout
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: 3),
                      alignment: .leading, spacing: 16) {
                ForEach(windows) { stat($0, warning: runout?.window.id == $0.id) }
            }
            .padding(Panel.rowPadding)

            if let runout {
                Rectangle().fill(Panel.separator).frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("At this pace, \(name(runout.window).lowercased()) runs out \(Self.when(runout.date, now: now)).")
                        .font(Panel.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(CharacterState.need.color)
                .padding(.horizontal, Panel.rowPadding)
                .padding(.vertical, 11)
            }
        }
    }

    private func stat(_ window: UsageLimitsStore.LimitWindow, warning: Bool) -> some View {
        let pct = min(100, max(0, window.percentLeft))
        let tint: Color = pct < 10 ? CharacterState.error.color : (pct < 25 || warning ? CharacterState.need.color : Panel.accent)
        return VStack(alignment: .leading, spacing: 6) {
            Text(name(window))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Panel.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(pct)")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundColor(Panel.primary)
                Text("%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Panel.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint).frame(width: max(3, g.size.width*CGFloat(pct)/100))
                }
            }
            .frame(height: 3)
            Text(window.resetsAt.map { "resets \(UsageLimitsStore.resetCountdown($0))" } ?? " ")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(Panel.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(window)), \(pct) percent left"
                            + (window.resetsAt.map { ", resets in \(UsageLimitsStore.resetCountdown($0))" } ?? ""))
    }

    private func name(_ window: UsageLimitsStore.LimitWindow) -> String {
        if window.label == "Session" { return "5-hour" }
        if let r = window.label.range(of: "Weekly · ") { return String(window.label[r.upperBound...]) + " weekly" }
        return window.label
    }

    private var firstRunout: (window: UsageLimitsStore.LimitWindow, date: Date)? {
        windows.compactMap { w -> (UsageLimitsStore.LimitWindow, Date)? in
            guard let resetsAt = w.resetsAt, let length = UsageForecast.windowLength(label: w.label),
                  case .runsOut(let date)? = UsageForecast.outcome(percentLeft: w.percentLeft, resetsAt: resetsAt,
                                                                    windowLength: length, now: now)
            else { return nil }
            return (w, date)
        }.min { $0.1 < $1.1 }.map { (window: $0.0, date: $0.1) }
    }

    /// "at 3:40 PM" today, "on Fri at 10:21 AM" otherwise.
    static func when(_ date: Date, now: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "at \(time)" }
        return "on \(date.formatted(.dateTime.weekday(.abbreviated))) at \(time)"
    }
}

// MARK: - Session row

private struct SessionMenuRow: View {
    let session: NotificationManager.SessionInfo
    let now: Date
    @State private var hovered = false

    var body: some View {
        let waiting = session.status == .needsInput || session.status == .needsPermission
        Button {
            TerminalLauncher.focusClaudeCode(sessionId: session.id, sourceBundleId: session.sourceBundleId,
                                             cwd: session.cwd, sourcePid: session.sourcePid)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(session.status.dotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.taskTitle ?? session.projectName)
                        .font(Panel.title)
                        .foregroundColor(Panel.primary)
                        .lineLimit(1)
                        .truncationMode(session.taskTitle == nil ? .middle : .tail)
                    HStack(spacing: 0) {
                        if session.taskTitle != nil {
                            Text("\(session.projectName) · ")
                                .foregroundColor(Panel.tertiary)
                                .lineLimit(1)
                                .layoutPriority(-1)
                        }
                        Text(session.status.activityLine(toolName: session.activeToolName, toolDetail: nil))
                            .foregroundColor(waiting ? CharacterState.need.color : Panel.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(Panel.subtitle)
                }
                Spacer(minLength: 8)
                Text(ElapsedFormatter.clock(Int(now.timeIntervalSince(session.startTime))))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(Panel.tertiary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(hovered ? Panel.primary : Panel.tertiary)
            }
            .padding(.horizontal, Panel.rowPadding)
            .padding(.vertical, 10)
            .background(Color.white.opacity(hovered ? 0.04 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open in terminal")
        .accessibilityHint("Opens this session in its terminal")
    }
}

/// Hands back the NSWindow a view lives in, once it has one.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    final class Probe: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onWindow = onWindow
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {}
}
