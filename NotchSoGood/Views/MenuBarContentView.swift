import SwiftUI
import Combine

/// The menu bar panel is the island, opened from the menu bar: the same black,
/// the same header strip (character left, runway ring right), the same session
/// rows as the notch's list, usage in the permission card's inner surface, and
/// the same equal pill buttons. Built from the island's own components so the
/// two can't drift apart.
struct MenuBarContentView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject private var limits = UsageLimitsStore.shared
    @ObservedObject private var characterSettings = CharacterSettings.shared

    @Environment(\.dismiss) private var dismiss
    @State private var window: NSWindow?
    @State private var axTrusted = AXIsProcessTrusted()
    private let axRecheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// The island's open width, so the panel reads as the same object.
    static let width: CGFloat = 360
    /// Island edge → text column, as in the notch (inset + card padding).
    private let column: CGFloat = Island.inset + Island.cardPadding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sessions
            VStack(spacing: Island.inset) {
                if !axTrusted { accessibilityCard }
                usageCard
                footer
            }
            .padding(.horizontal, Island.inset)
            .padding(.top, 6)
            .padding(.bottom, Island.inset)
        }
        .frame(width: Self.width)
        // Fill the whole window, top-aligned: the window can be taller than the
        // content for a moment while it resizes, and its own background must
        // never show (it was white in Light mode).
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .background(WindowReader { window in
            self.window = window
            window?.appearance = NSAppearance(named: .darkAqua)
            window?.backgroundColor = .black
        })
        .environment(\.colorScheme, .dark)
        .onAppear {
            axTrusted = AXIsProcessTrusted()
            limits.refresh(force: true)
        }
        .onReceive(axRecheck) { _ in axTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Header strip

    private var sessionsList: [NotificationManager.SessionInfo] { notificationManager.orderedSessions }

    private var waitingCount: Int {
        sessionsList.filter { $0.status == .needsInput || $0.status == .needsPermission }.count
    }

    private var characterState: CharacterState {
        if waitingCount > 0 { return .need }
        return sessionsList.isEmpty ? .idle : .work
    }

    private var statusLine: String {
        if sessionsList.isEmpty { return "\(characterSettings.kind.displayName) is off duty" }
        if waitingCount > 0 { return "\(waitingCount) waiting on you" }
        return "\(sessionsList.count) session\(sessionsList.count == 1 ? "" : "s") working"
    }

    private var runway: UsageLimitsStore.LimitWindow? {
        limits.sessionWindow(for: sessionsList.first?.agentSource ?? .claude) ?? limits.windows.first { $0.label == "Session" }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CharacterStill(state: characterState, framing: .portrait, size: 40)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notch So Good")
                    .font(Island.title)
                    .foregroundColor(Island.primary)
                Text(statusLine)
                    .font(Island.meta)
                    .foregroundColor(waitingCount > 0 ? CharacterState.need.color : Island.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let runway {
                RunwayIndicator(percentLeft: runway.percentLeft)
            }
        }
        .padding(.leading, column - 10)
        .padding(.trailing, column)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Sessions (the notch's own rows)

    @ViewBuilder
    private var sessions: some View {
        let all = sessionsList
        if !all.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    ForEach(all.prefix(6)) { session in
                        Button {
                            TerminalLauncher.focusClaudeCode(sessionId: session.id, sourceBundleId: session.sourceBundleId,
                                                             cwd: session.cwd, sourcePid: session.sourcePid)
                        } label: {
                            IslandSessionRow(session: session, now: context.date)
                                .padding(.leading, column - Island.inset - 3.5)
                                .padding(.trailing, column - Island.inset)
                                .frame(height: PillLayout.sessionRow)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(IslandRowStyle())
                        .accessibilityLabel(SessionRowParts.accessibilityLabel(session, now: context.date))
                        .accessibilityHint("Opens this session in its terminal")
                    }
                    if all.count > 6 {
                        Text("\(all.count - 6) more in the notch")
                            .font(Island.meta)
                            .foregroundColor(Island.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, column - Island.inset)
                            .frame(height: 30)
                    }
                }
                .padding(.horizontal, Island.inset)
            }
        }
    }

    // MARK: - Usage (the permission card's inner surface)

    private var usageCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                let windows = limits.windows
                if windows.isEmpty {
                    HStack(spacing: 8) {
                        StatusDot(color: Island.tertiary, size: 6)
                        Text(placeholderText)
                            .font(Island.meta)
                            .foregroundColor(Island.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if limits.status != .loading {
                            Button("Retry") { limits.refresh(force: true) }
                                .buttonStyle(.plain)
                                .font(Island.meta)
                                .foregroundColor(Island.primary)
                        }
                    }
                } else {
                    ForEach(Array(agents(windows).enumerated()), id: \.element) { index, agent in
                        if index > 0 { Rectangle().fill(Island.hairline).frame(height: 1) }
                        agentUsage(agent, windows: windows.filter { $0.source == agent }, now: context.date)
                    }
                }
            }
            .padding(Island.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Island.cardRadius, style: .continuous)
                    .fill(Island.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Island.cardRadius, style: .continuous)
                            .strokeBorder(Island.hairline, lineWidth: 1)
                    )
            )
        }
    }

    private func agentUsage(_ agent: AgentSource, windows: [UsageLimitsStore.LimitWindow], now: Date) -> some View {
        let runout = Self.firstRunout(windows, now: now)
        return VStack(alignment: .leading, spacing: 9) {
            Text(agent == .claude ? "Claude Code" : agent.displayName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Island.tertiary)
            ForEach(windows) { window in
                HStack(spacing: 10) {
                    UsageRing(percentLeft: window.percentLeft, diameter: 12, lineWidth: 2.5,
                              tint: UsageTint.notch(window.percentLeft), track: Color.white.opacity(0.16))
                    Text(Self.name(window))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Island.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let resetsAt = window.resetsAt {
                        Text(UsageLimitsStore.resetCountdown(resetsAt))
                            .font(Island.numeric)
                            .foregroundColor(runout?.id == window.id ? CharacterState.need.color : Island.tertiary)
                    }
                    Text("\(window.percentLeft)%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(Island.primary)
                        .frame(minWidth: 38, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Self.name(window)), \(window.percentLeft) percent left"
                                    + (window.resetsAt.map { ", resets in \(UsageLimitsStore.resetCountdown($0))" } ?? ""))
            }
            if let runout, let date = runout.runsOut {
                HStack(spacing: 8) {
                    StatusDot(color: CharacterState.need.color, size: 6)
                    Text("At this pace, \(Self.name(runout).lowercased()) runs out \(Self.when(date, now: now))")
                        .font(Island.meta)
                        .foregroundColor(CharacterState.need.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
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

    private static func name(_ window: UsageLimitsStore.LimitWindow) -> String {
        if window.label == "Session" { return "5-hour" }
        if let r = window.label.range(of: "Weekly · ") { return "Weekly · " + window.label[r.upperBound...] }
        return window.label
    }

    private static func firstRunout(_ windows: [UsageLimitsStore.LimitWindow], now: Date) -> UsageLimitsStore.LimitWindow.WithRunout? {
        windows.compactMap { w -> UsageLimitsStore.LimitWindow.WithRunout? in
            guard let resetsAt = w.resetsAt, let length = UsageForecast.windowLength(label: w.label),
                  case .runsOut(let date)? = UsageForecast.outcome(percentLeft: w.percentLeft, resetsAt: resetsAt,
                                                                    windowLength: length, now: now)
            else { return nil }
            return .init(window: w, runsOut: date)
        }.min { ($0.runsOut ?? .distantFuture) < ($1.runsOut ?? .distantFuture) }
    }

    private static func name(_ runout: UsageLimitsStore.LimitWindow.WithRunout) -> String { name(runout.window) }

    /// "at 3:40 PM" today, "on Fri at 10:21 AM" otherwise.
    private static func when(_ date: Date, now: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "at \(time)" }
        return "on \(date.formatted(.dateTime.weekday(.abbreviated))) at \(time)"
    }

    // MARK: - Accessibility

    private var accessibilityCard: some View {
        HStack(spacing: 10) {
            StatusDot(color: CharacterState.need.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Accessibility")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Island.primary)
                Text("So a click jumps to the exact terminal window.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Island.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(Island.button)
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.94)))
        }
        .padding(Island.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Island.cardRadius, style: .continuous)
                .fill(Island.card)
                .overlay(RoundedRectangle(cornerRadius: Island.cardRadius, style: .continuous).strokeBorder(Island.hairline, lineWidth: 1))
        )
    }

    // MARK: - Footer (the permission card's buttons)

    private var footer: some View {
        HStack(spacing: 8) {
            IslandButton(label: "Quit", shortcut: "⌘Q", style: .secondary, hint: "Quits Notch So Good") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            IslandButton(label: "Settings", shortcut: "⌘,", style: .primary, hint: "Opens Settings") {
                dismiss()
                window?.orderOut(nil)
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

extension UsageLimitsStore.LimitWindow {
    struct WithRunout {
        let window: UsageLimitsStore.LimitWindow
        let runsOut: Date?
        var id: String { window.id }
        var label: String { window.label }
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
