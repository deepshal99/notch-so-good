import SwiftUI
import AppKit

/// Controller→view signal so the exit can mirror the entrance (see PillDataSource pattern).
final class NotificationPhase: ObservableObject {
    @Published var dismissing = false
}

/// A card that drops out of the notch. It is the open pill's exact shape and
/// top strip (character on the left, runway on the right), so a card reads as
/// the pill opening rather than something new arriving.
///
/// Permission requests get an inner card: what's being asked, by whom, the
/// exact command, and three equal buttons. Everything else is a calm summary.
struct NotchNotificationView: View {
    let notification: NotchNotification
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: () -> Void
    let onDismiss: () -> Void
    let onApprove: (() -> Void)?
    let onAlwaysAllow: (() -> Void)?
    let onDeny: (() -> Void)?
    @ObservedObject var phase: NotificationPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var limits = UsageLimitsStore.shared
    @State private var expanded = false
    @State private var contentAppeared = false
    @State private var hovered = false

    private let session: NotificationManager.SessionInfo?
    private let branch: String?

    init(
        notification: NotchNotification,
        hasNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        onTap: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onApprove: (() -> Void)? = nil,
        onAlwaysAllow: (() -> Void)? = nil,
        onDeny: (() -> Void)? = nil,
        phase: NotificationPhase = NotificationPhase(),
        session: NotificationManager.SessionInfo? = nil,
        appearImmediately: Bool = false
    ) {
        self.notification = notification
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.onTap = onTap
        self.onDismiss = onDismiss
        self.onApprove = onApprove
        self.onAlwaysAllow = onAlwaysAllow
        self.onDeny = onDeny
        self.phase = phase
        self.session = session
        self.branch = GitBranch.current(in: session?.cwd)
        if appearImmediately {
            _expanded = State(initialValue: true)
            _contentAppeared = State(initialValue: true)
        }
    }

    // MARK: - Layout (shared with the window controller)

    /// The window controller sizes the panel before SwiftUI lays anything out,
    /// so both read the card's geometry from here.
    enum Metrics {
        /// The notch shape's concave top fillets put its side walls this far
        /// inside the panel. All content is laid out from the wall, not the panel.
        /// Same as the open pill's, so a card and the hovered pill are one shape.
        static let wall: CGFloat = 9

        /// Exactly the open pill's width on notched displays, so the character
        /// and runway sit where they do when you hover the pill.
        static func panelWidth(notchWidth: CGFloat, hasNotch: Bool) -> CGFloat {
            hasNotch ? notchWidth + 2*PillLayout.wingExpanded : 420
        }

        static func islandWidth(_ panelWidth: CGFloat) -> CGFloat { panelWidth - 2*wall }

        /// The strip level with the notch. Displays without one get a strip of
        /// the same proportions so the card looks identical.
        static func headerHeight(notchHeight: CGFloat, hasNotch: Bool) -> CGFloat {
            hasNotch ? notchHeight : 34
        }

        static let headerGap: CGFloat = 4

        /// Where the character sits in the header strip, from the island wall.
        static let characterSlot = CGRect(x: Island.contentInset - 17, y: 0, width: PillLayout.wingCollapsed, height: 37)
        static let titleRow: CGFloat = 20
        static let metaRow: CGFloat = 20
        static let rowGap: CGFloat = 8
        static let wellPadding: CGFloat = 10
        static let buttonHeight: CGFloat = 32
        static let maxCommandLines = 3
        static let maxMessageLines = 3

        static var monoLine: CGFloat { lineHeight(NSFont.monospacedSystemFont(ofSize: Island.monoSize, weight: .regular)) }
        static var bodyLine: CGFloat { lineHeight(NSFont.systemFont(ofSize: Island.bodySize)) + 2 }

        /// Height of everything below the header strip.
        static func contentHeight(for notification: NotchNotification, panelWidth: CGFloat) -> CGFloat {
            if notification.isInteractivePermission {
                let lines = commandLines(notification, panelWidth: panelWidth)
                let well = 2*wellPadding + CGFloat(lines)*monoLine
                let card = Island.cardPadding + titleRow + rowGap + metaRow + 10 + well + 12 + buttonHeight + Island.cardPadding
                return headerGap + card + Island.inset
            }
            let lines = messageLines(notification, panelWidth: panelWidth)
            return headerGap + 4 + titleRow + 6 + metaRow + 8 + CGFloat(lines)*bodyLine + 16
        }

        static func commandLines(_ notification: NotchNotification, panelWidth: CGFloat) -> Int {
            let wellWidth = islandWidth(panelWidth) - 2*(Island.inset + Island.cardPadding) - 2*wellPadding
            return lineCount(notification.message, font: NSFont.monospacedSystemFont(ofSize: Island.monoSize, weight: .regular),
                             width: wellWidth, max: maxCommandLines)
        }

        static func messageLines(_ notification: NotchNotification, panelWidth: CGFloat) -> Int {
            lineCount(notification.message, font: NSFont.systemFont(ofSize: Island.bodySize),
                      width: islandWidth(panelWidth) - 2*Island.contentInset, max: maxMessageLines)
        }

        private static func lineHeight(_ font: NSFont) -> CGFloat {
            ceil(NSLayoutManager().defaultLineHeight(for: font))
        }

        /// Lines the text wraps to at this width, measured with the same font
        /// SwiftUI will draw it in (a couple of points narrower, to be safe).
        static func lineCount(_ text: String, font: NSFont, width: CGFloat, max maxLines: Int) -> Int {
            let storage = NSTextStorage(string: text, attributes: [.font: font])
            let container = NSTextContainer(size: CGSize(width: Swift.max(40, width - 2), height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            let manager = NSLayoutManager()
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)
            var lines = 0
            var index = 0
            while index < manager.numberOfGlyphs, lines < maxLines {
                var range = NSRange()
                manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
                index = NSMaxRange(range)
                lines += 1
            }
            return Swift.min(maxLines, Swift.max(1, lines))
        }
    }

    // MARK: - Derived content

    private var isPermission: Bool { notification.isInteractivePermission }
    private var characterState: CharacterState { CharacterState(notification: notification) }
    private var isDestructive: Bool { isPermission && CommandRisk.looksDestructive(notification.message) }
    private var accent: Color { isDestructive ? CharacterState.error.color : characterState.color }
    private var headerHeight: CGFloat { Metrics.headerHeight(notchHeight: notchHeight, hasNotch: hasNotch) }

    private var title: String {
        switch notification.type {
        case .complete: return notification.title ?? "Finished"
        case .question: return notification.title ?? "Needs your input"
        case .permission: return notification.title ?? "Needs your go-ahead"
        case .general: return notification.displayTitle
        }
    }

    private var projectName: String? { session?.projectName }

    /// "Bash"; MCP tools show their server ("github"), not the mangled name.
    private var toolChip: String? {
        guard let tool = notification.toolName else { return nil }
        return SessionStatus.mcpServer(tool) ?? tool
    }

    private var runway: UsageLimitsStore.LimitWindow? {
        let source = session?.agentSource ?? .claude
        return limits.windows.first { $0.source == source && $0.label == "Session" }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width
            let width = Metrics.islandWidth(panelWidth)
            let height = geo.size.height
            let startScaleX = hasNotch ? (notchWidth + 8) / panelWidth : 0.6
            let startScaleY = hasNotch ? (notchHeight + 2) / height : 0.2

            ZStack(alignment: .top) {
                // Only the black shape stretches out of the notch; scaling text or
                // the character non-uniformly would distort them.
                islandShape
                    .fill(Color.black)
                    .overlay(
                        // A faint lit edge at the bottom so the island separates from dark wallpapers.
                        islandShape
                            .stroke(
                                LinearGradient(colors: [.clear, .clear, Color.white.opacity(0.07)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                    )
                    .frame(width: hasNotch ? panelWidth : width)
                    .scaleEffect(x: expanded ? 1 : startScaleX, y: expanded ? 1 : startScaleY, anchor: .top)

                VStack(spacing: 0) {
                    header(width: width)
                    Group {
                        if isPermission {
                            permissionCard(panelWidth: panelWidth)
                                .padding(.horizontal, Island.inset)
                                .padding(.top, Metrics.headerGap)
                        } else {
                            summary(panelWidth: panelWidth)
                                .padding(.horizontal, Island.contentInset)
                                .padding(.top, Metrics.headerGap + 4)
                        }
                    }
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared || reduceMotion ? 0 : -6)
                    Spacer(minLength: 0)
                }
                .frame(width: width, height: height)
            }
            .frame(width: panelWidth, height: height, alignment: .top)
            // Content never shows outside the island while it's still growing.
            .mask(
                islandShape
                    .frame(width: hasNotch ? panelWidth : width, height: height)
                    .scaleEffect(x: expanded ? 1 : startScaleX, y: expanded ? 1 : startScaleY, anchor: .top)
            )
            .contentShape(islandShape)
            .onTapGesture { if !isPermission { onTap() } }
            .onHover { hovered = $0 }
            .accessibilityElement(children: isPermission ? .contain : .combine)
            .accessibilityLabel("\(title). \(notification.message)")
            .accessibilityHint(isPermission ? "Control Option A to allow, Control Option D to deny" : "Opens the session in its terminal")
        }
        .onAppear(perform: animateIn)
        .onChange(of: phase.dismissing) { _, dismissing in
            guard dismissing else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { expanded = false }
            withAnimation(.easeOut(duration: 0.12)) { contentAppeared = false }
        }
    }

    private var islandShape: AnyShape {
        hasNotch
            ? AnyShape(NotchShape(topRadius: Metrics.wall, bottomRadius: Island.radius))
            : AnyShape(RoundedRectangle(cornerRadius: Island.radius, style: .continuous))
    }

    // MARK: - Header strip (level with the notch)

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            CharacterView(state: characterState, framing: .pill)
                .frame(width: Metrics.characterSlot.width, height: headerHeight)
                .padding(.leading, Metrics.characterSlot.minX)
            Spacer(minLength: 0)
            if let runway {
                RunwayIndicator(percentLeft: runway.percentLeft)
                    .padding(.trailing, Island.contentInset)
            }
        }
        .frame(width: width, height: headerHeight)
        .opacity(contentAppeared ? 1 : 0)
    }

    // MARK: - Permission card

    private func permissionCard(panelWidth: CGFloat) -> some View {
        let lines = Metrics.commandLines(notification, panelWidth: panelWidth)
        return VStack(alignment: .leading, spacing: 0) {
            // Title row: what's being asked, and how long it's been waiting.
            HStack(spacing: 8) {
                StatusDot(color: accent)
                Text(title)
                    .font(Island.title)
                    .foregroundColor(Island.primary)
                    .lineLimit(1)
                if isDestructive {
                    Text("Destructive")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: "FF8A80"))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Capsule().fill(CharacterState.error.color.opacity(0.16)))
                }
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.waitLabel(ctx.date.timeIntervalSince(notification.timestamp)))
                        .font(Island.numeric)
                        .foregroundColor(Island.tertiary)
                }
                .accessibilityLabel("waiting")
            }
            .frame(height: Metrics.titleRow)

            // Who's asking.
            HStack(spacing: 8) {
                if let toolChip { Chip(text: toolChip) }
                if let projectName {
                    Text(projectName)
                        .font(Island.meta)
                        .foregroundColor(Island.secondary)
                        .lineLimit(1)
                }
                if let branch { BranchLabel(branch: branch).layoutPriority(-1) }
                Spacer(minLength: 0)
            }
            .frame(height: Metrics.metaRow)
            .padding(.top, Metrics.rowGap)

            // The exact command, in a recessed well.
            Text(notification.message)
                .font(Island.mono)
                .foregroundColor(Color.white.opacity(0.9))
                .lineLimit(lines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: CGFloat(lines)*Metrics.monoLine, alignment: .topLeading)
                .padding(Metrics.wellPadding)
                .background(
                    RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                        .fill(Island.well)
                        .overlay(
                            RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                                .strokeBorder(isDestructive ? CharacterState.error.color.opacity(0.35) : Island.hairline, lineWidth: 1)
                        )
                )
                .padding(.top, 10)

            HStack(spacing: 8) {
                IslandButton(label: "Deny", shortcut: "⌃⌥D", style: .secondary, hint: "Blocks this tool call") { onDeny?() }
                IslandButton(label: "Always allow", shortcut: nil, style: .secondary, hint: "Adds a permanent allow rule to your settings") { onAlwaysAllow?() }
                IslandButton(label: "Allow", shortcut: "⌃⌥A", style: .primary, hint: "Allows this tool call once") { onApprove?() }
            }
            .padding(.top, 12)
        }
        .padding(Island.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Island.cardRadius, style: .continuous)
                .fill(Island.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Island.cardRadius, style: .continuous)
                        .strokeBorder(Island.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Summary (done, questions, heads-ups)

    private func summary(panelWidth: CGFloat) -> some View {
        let lines = Metrics.messageLines(notification, panelWidth: panelWidth)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if characterState == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, accent)
                        .frame(width: 14, height: 14)
                } else {
                    StatusDot(color: accent)
                }
                Text(title)
                    .font(Island.title)
                    .foregroundColor(Island.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("just now")
                    .font(Island.numeric)
                    .foregroundColor(Island.tertiary)
            }
            .frame(height: Metrics.titleRow)

            HStack(spacing: 8) {
                // Title first; the project, agent and branch join only when they
                // fit whole, so nothing is ever cut to a stub.
                ViewThatFits(in: .horizontal) {
                    summaryMeta(project: true, agent: true, branch: true)
                    summaryMeta(project: true, agent: true, branch: false)
                    summaryMeta(project: false, agent: false, branch: false)
                }
                Spacer(minLength: 0)
                if session != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(hovered ? Island.primary : Island.tertiary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(hovered ? 0.14 : 0.07)))
                        .animation(Island.press, value: hovered)
                        .help("Open in terminal")
                }
            }
            .frame(height: Metrics.metaRow)
            .padding(.top, 6)

            Text(notification.message)
                .font(Island.body)
                .foregroundColor(Color.white.opacity(0.74))
                .lineSpacing(2)
                .lineLimit(lines)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: CGFloat(lines)*Metrics.bodyLine, alignment: .topLeading)
                .padding(.top, 8)
        }
    }

    private func summaryMeta(project: Bool, agent: Bool, branch showBranch: Bool) -> some View {
        HStack(spacing: 8) {
            Text(session?.taskTitle ?? projectName ?? "Claude Code")
                .font(Island.meta)
                .foregroundColor(Island.secondary)
                .lineLimit(1)
            if project, session?.taskTitle != nil, let projectName {
                Text(projectName)
                    .font(Island.meta)
                    .foregroundColor(Island.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if agent, let session, session.agentSource != .claude {
                Chip(text: session.agentSource.displayName, mono: false)
            }
            if showBranch, let branch {
                BranchLabel(branch: branch).fixedSize()
            }
        }
    }

    /// "0:12" — how long the agent has been waiting on you.
    static func waitLabel(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? "\(s/3600)h \((s%3600)/60)m" : "\(s/60):\(String(format: "%02d", s%60))"
    }

    // MARK: - Animation

    private func animateIn() {
        guard !expanded else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { expanded = true; contentAppeared = true }
            return
        }
        withAnimation(Island.spring) { expanded = true }
        withAnimation(.easeOut(duration: 0.22).delay(0.12)) { contentAppeared = true }
    }
}

// MARK: - Buttons

/// Equal-width pill button. Primary is white on black, like the system's own
/// notch controls; secondary sits quietly on the card.
struct IslandButton: View {
    enum Style { case primary, secondary }

    let label: String
    let shortcut: String?
    let style: Style
    var hint: String? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(Island.button)
                    .lineLimit(1)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.45)
                        .lineLimit(1)
                }
            }
            .foregroundColor(style == .primary ? Color.black : Island.primary)
            .frame(maxWidth: .infinity)
            .frame(height: NotchNotificationView.Metrics.buttonHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(style == .primary
                          ? Color.white.opacity(hovered ? 1 : 0.94)
                          : (hovered ? Island.controlHover : Island.control))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovered = $0 }
        .animation(Island.press, value: hovered)
        .help(shortcut.map { "\(label) (\($0))" } ?? label)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }
}
