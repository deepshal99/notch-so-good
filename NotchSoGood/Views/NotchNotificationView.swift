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
/// Cards that wait for an answer get an inner card: what's being asked, by
/// whom, the exact command (or the plan, or the question's options), and equal
/// buttons. Everything else is a calm summary.
struct NotchNotificationView: View {
    let notification: NotchNotification
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: () -> Void
    let onDismiss: () -> Void
    /// How the user answered a waiting card.
    let onRespond: ((CardResponse) -> Void)?
    @ObservedObject var phase: NotificationPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var limits = UsageLimitsStore.shared
    @State private var expanded = false
    @State private var contentAppeared = false
    @State private var hovered = false
    /// Questions: which one is showing, and what's picked so far.
    @State private var questionIndex = 0
    @State private var picked: [Int: Set<Int>] = [:]
    /// Typed "Other" answers, per question.
    @State private var typed: [Int: String] = [:]

    private let session: NotificationManager.SessionInfo?
    private let branch: String?

    init(
        notification: NotchNotification,
        hasNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        onTap: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onRespond: ((CardResponse) -> Void)? = nil,
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
        self.onRespond = onRespond
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
        /// How far the character may hang below the strip.
        static let characterOverhang: CGFloat = 14
        static let titleRow: CGFloat = 20
        static let metaRow: CGFloat = 20
        static let rowGap: CGFloat = 8
        static let wellPadding: CGFloat = 10
        static let buttonHeight: CGFloat = 32
        /// The full command always shows: up to this many lines, then it scrolls.
        static let maxCommandLines = 6
        static let maxPlanLines = 7
        static let maxMessageLines = 3
        static let maxQuestionLines = 3
        static let captionRow: CGFloat = 16
        static let optionGap: CGFloat = 6
        static func optionHeight(_ option: AgentQuestion.Option) -> CGFloat { option.description.isEmpty ? 34 : 44 }
        static let otherHeight: CGFloat = 34

        static var monoLine: CGFloat { lineHeight(NSFont.monospacedSystemFont(ofSize: Island.monoSize, weight: .regular)) }
        static var bodyLine: CGFloat { lineHeight(NSFont.systemFont(ofSize: Island.bodySize)) + 2 }

        /// Height of everything below the header strip.
        static func contentHeight(for notification: NotchNotification, panelWidth: CGFloat) -> CGFloat {
            if let interaction = notification.interaction {
                let top = Island.cardPadding + titleRow + rowGap + metaRow
                var card: CGFloat
                switch interaction {
                case .permission(let always):
                    let well = 2*wellPadding + CGFloat(commandLines(notification, panelWidth: panelWidth).shown)*monoLine
                    card = top + (hasDescription(notification) ? 6 + bodyLine : 0) + 10 + well + 12 + buttonHeight
                    if always != nil { card += 8 + captionRow }
                case .plan:
                    let lines = planLines(notification, panelWidth: panelWidth).shown
                    card = top + 6 + bodyLine + (lines > 0 ? 10 + 2*wellPadding + CGFloat(lines)*bodyLine : 0) + 12 + buttonHeight
                case .question(let questions):
                    // Sized for the tallest question, so stepping through never resizes the card.
                    let tallest = questions.map { q -> CGFloat in
                        let lines = CGFloat(questionLines(q.question, panelWidth: panelWidth))
                        let options = q.options.map(optionHeight).reduce(0, +) + CGFloat(q.options.count)*optionGap + otherHeight
                        return 8 + lines*bodyLine + 10 + options + (q.multiSelect ? 12 + buttonHeight : 10 + captionRow)
                    }.max() ?? 0
                    card = top + tallest
                }
                return headerGap + card + Island.cardPadding + Island.inset
            }
            let lines = messageLines(notification, panelWidth: panelWidth)
            return headerGap + 4 + titleRow + 6 + metaRow + 8 + CGFloat(lines)*bodyLine + 16
        }

        static func wellWidth(_ panelWidth: CGFloat) -> CGFloat {
            islandWidth(panelWidth) - 2*(Island.inset + Island.cardPadding) - 2*wellPadding
        }

        /// Lines shown, and whether there's more (then the well scrolls).
        static func commandLines(_ notification: NotchNotification, panelWidth: CGFloat) -> (shown: Int, overflows: Bool) {
            let text = notification.detail ?? notification.message
            let lines = lineCount(text, font: NSFont.monospacedSystemFont(ofSize: Island.monoSize, weight: .regular),
                                  width: wellWidth(panelWidth), max: maxCommandLines + 1)
            return (min(lines, maxCommandLines), lines > maxCommandLines)
        }

        static func planLines(_ notification: NotchNotification, panelWidth: CGFloat) -> (shown: Int, overflows: Bool) {
            guard let plan = notification.detail else { return (0, false) }
            let lines = lineCount(plan, font: NSFont.systemFont(ofSize: Island.bodySize), width: wellWidth(panelWidth), max: maxPlanLines + 1)
            return (min(lines, maxPlanLines), lines > maxPlanLines)
        }

        static func questionLines(_ question: String, panelWidth: CGFloat) -> Int {
            lineCount(question, font: NSFont.systemFont(ofSize: Island.bodySize),
                      width: islandWidth(panelWidth) - 2*(Island.inset + Island.cardPadding), max: maxQuestionLines)
        }

        /// Claude's own one-line description of the call ("Remove node_modules"), when it adds something.
        static func hasDescription(_ notification: NotchNotification) -> Bool {
            guard let detail = notification.detail, !notification.message.isEmpty else { return false }
            return !detail.contains(notification.message)
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
    /// Judged on the full command, never a shortened one.
    private var isDestructive: Bool {
        guard isPermission, case .permission = notification.interaction else { return false }
        return CommandRisk.looksDestructive(notification.detail ?? notification.message)
    }
    private var accent: Color { isDestructive ? CharacterState.error.color : characterState.color }
    private var headerHeight: CGFloat { Metrics.headerHeight(notchHeight: notchHeight, hasNotch: hasNotch) }

    private var title: String {
        switch notification.type {
        case .complete: return notification.title ?? "Finished"
        case .question: return notification.title ?? "Needs your input"
        case .permission: return notification.title ?? "Needs your go-ahead"
        case .error: return notification.title ?? "Stopped"
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
                    // Above the card, so Peek can hang over its top edge.
                    header(width: width).zIndex(1)
                    Group {
                        if isPermission {
                            waitingCard(panelWidth: panelWidth)
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
            .accessibilityHint(accessibilityHint)
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
            // Room below the strip, so a pose that reaches down (and its glow)
            // isn't cut off at the strip's edge.
            CharacterView(state: characterState, framing: .notch(height: headerHeight))
                .frame(width: Metrics.characterSlot.width, height: headerHeight + Metrics.characterOverhang)
                .frame(width: Metrics.characterSlot.width, height: headerHeight, alignment: .top)
                .allowsHitTesting(false)
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

    // MARK: - Waiting cards

    private var accessibilityHint: String {
        switch notification.interaction {
        case .permission: return "Control Option A to allow, Control Option D to deny"
        case .plan: return "Control Option A to approve the plan"
        case .question: return "Choose an answer"
        case nil: return "Opens the session in its terminal"
        }
    }

    private func waitingCard(panelWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            metaRow.padding(.top, Metrics.rowGap)
            switch notification.interaction {
            case .plan:
                planBody(panelWidth: panelWidth)
            case .question(let questions):
                questionBody(questions, panelWidth: panelWidth)
            default:
                permissionBody(panelWidth: panelWidth)
            }
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

    /// What's being asked, and how long it's been waiting.
    private var titleRow: some View {
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
            if case .question(let questions) = notification.interaction, questions.count > 1 {
                Text("\(questionIndex + 1) of \(questions.count)")
                    .font(Island.numeric)
                    .foregroundColor(Island.tertiary)
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
    }

    /// Who's asking.
    private var metaRow: some View {
        HStack(spacing: 8) {
            if let session {
                Circle().fill(session.color).frame(width: 7, height: 7)
            }
            if let toolChip, case .permission = notification.interaction { Chip(text: toolChip) }
            if let session, session.agentSource != .claude { Chip(text: session.agentSource.displayName, mono: false) }
            if let projectName {
                Text(session?.taskTitle ?? projectName)
                    .font(Island.meta)
                    .foregroundColor(Island.secondary)
                    .lineLimit(1)
            }
            if let branch { BranchLabel(branch: branch).layoutPriority(-1) }
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.metaRow)
    }

    private func well<Content: View>(lines: Int, lineHeight: CGFloat, scrolls: Bool, danger: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        Group {
            if scrolls {
                ScrollView(.vertical) { content().frame(maxWidth: .infinity, alignment: .topLeading) }
                    .scrollIndicators(.visible)
            } else {
                content().frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: CGFloat(lines)*lineHeight, alignment: .topLeading)
        .padding(Metrics.wellPadding)
        .background(
            RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                .fill(Island.well)
                .overlay(
                    RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                        .strokeBorder(danger ? CharacterState.error.color.opacity(0.35) : Island.hairline, lineWidth: 1)
                )
        )
    }

    // A tool call: Claude's description, the exact command, Deny / (Always) / Allow.
    @ViewBuilder
    private func permissionBody(panelWidth: CGFloat) -> some View {
        let lines = Metrics.commandLines(notification, panelWidth: panelWidth)
        if Metrics.hasDescription(notification) {
            Text(notification.message)
                .font(Island.body)
                .foregroundColor(Island.secondary)
                .lineLimit(1)
                .frame(height: Metrics.bodyLine, alignment: .leading)
                .padding(.top, 6)
        }
        well(lines: lines.shown, lineHeight: Metrics.monoLine, scrolls: lines.overflows, danger: isDestructive) {
            Text(Self.commandText(notification.detail ?? notification.message, isEdit: isFileChange))
                .font(Island.mono)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.top, 10)

        let always: CardInteraction.AlwaysRule? = {
            if case .permission(let rule) = notification.interaction { return rule }
            return nil
        }()
        HStack(spacing: 8) {
            IslandButton(label: "Deny", shortcut: "⌃⌥D", style: .secondary, hint: "Blocks this tool call") { onRespond?(.deny) }
            if let always {
                IslandButton(label: "Always allow", shortcut: nil, style: .secondary,
                             hint: "Saves \(always.label) for \(always.scope)") { onRespond?(.allowAlways) }
            }
            IslandButton(label: "Allow", shortcut: "⌃⌥A", style: .primary, hint: "Allows this tool call once") { onRespond?(.allow) }
        }
        .padding(.top, 12)
        if let always {
            // Exactly what "Always allow" saves, and where: no surprises.
            Text("Always allow saves \(always.label) for \(always.scope)")
                .font(Island.caption)
                .foregroundColor(Island.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: Metrics.captionRow)
                .padding(.top, 8)
        }
    }

    private var isFileChange: Bool {
        ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(notification.toolName ?? "")
    }

    /// The command as is; a file change as its path, then removed lines in
    /// red and added lines in green.
    static func commandText(_ text: String, isEdit: Bool) -> AttributedString {
        guard isEdit else {
            var plain = AttributedString(text)
            plain.foregroundColor = Color.white.opacity(0.9)
            return plain
        }
        var out = AttributedString()
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            var part = AttributedString((i > 0 ? "\n" : "") + line)
            if i == 0 { part.foregroundColor = Island.secondary }
            else if line.hasPrefix("- ") { part.foregroundColor = Color(hex: "FF8A80") }
            else if line.hasPrefix("+ ") { part.foregroundColor = Color(hex: "7FE0A6") }
            else { part.foregroundColor = Color.white.opacity(0.9) }
            out += part
        }
        return out
    }

    // A plan: its title, the start of it, and how to go ahead.
    @ViewBuilder
    private func planBody(panelWidth: CGFloat) -> some View {
        Text(notification.message)
            .font(Island.body.weight(.medium))
            .foregroundColor(Island.primary)
            .lineLimit(1)
            .frame(height: Metrics.bodyLine, alignment: .leading)
            .padding(.top, 6)
        let lines = Metrics.planLines(notification, panelWidth: panelWidth)
        if lines.shown > 0, let plan = notification.detail {
            well(lines: lines.shown, lineHeight: Metrics.bodyLine, scrolls: lines.overflows) {
                Text(plan)
                    .font(Island.body)
                    .foregroundColor(Color.white.opacity(0.74))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
        HStack(spacing: 8) {
            IslandButton(label: "In terminal", shortcut: "⌃⌥D", style: .secondary, hint: "Answer in the terminal, to give feedback") { onRespond?(.handOff) }
            IslandButton(label: "Auto-accept", shortcut: nil, style: .secondary, hint: "Approve, and accept its edits without asking") { onRespond?(.approvePlan(acceptEdits: true)) }
            IslandButton(label: "Approve", shortcut: "⌃⌥A", style: .primary, hint: "Approve the plan") { onRespond?(.approvePlan(acceptEdits: false)) }
        }
        .padding(.top, 12)
    }

    // Questions: the options as buttons, one question at a time.
    @ViewBuilder
    private func questionBody(_ questions: [AgentQuestion], panelWidth: CGFloat) -> some View {
        let index = min(questionIndex, questions.count - 1)
        let question = questions[index]
        let selected = picked[index] ?? []
        Text(question.question)
            .font(Island.body)
            .foregroundColor(Color.white.opacity(0.86))
            .lineSpacing(2)
            .lineLimit(Metrics.maxQuestionLines)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        VStack(spacing: Metrics.optionGap) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                OptionRow(option: option, multiSelect: question.multiSelect, selected: selected.contains(offset)) {
                    choose(offset, in: questions)
                }
            }
            OtherAnswerField(text: Binding(get: { typed[index] ?? "" }, set: { typed[index] = $0 })) {
                // Return: a single choice goes straight in; a multi-select keeps
                // it alongside the ticked ones until Send.
                guard !(typed[index] ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return }
                if !question.multiSelect { picked[index] = [] ; advance(in: questions) }
            }
        }
        .padding(.top, 10)
        if question.multiSelect {
            HStack(spacing: 8) {
                IslandButton(label: "In \(answerElsewhere)", shortcut: nil, style: .secondary, hint: "Answer in \(answerElsewhere)") { onRespond?(.handOff) }
                let hasAnswer = !selected.isEmpty || !(typed[index] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                IslandButton(label: index + 1 < questions.count ? "Next" : "Send", shortcut: nil, style: .primary, hint: "Send these answers") {
                    advance(in: questions)
                }
                .disabled(!hasAnswer)
                .opacity(hasAnswer ? 1 : 0.5)
            }
            .padding(.top, 12)
        } else {
            HStack {
                Spacer()
                Button { onRespond?(.handOff) } label: {
                    Text("Answer in \(answerElsewhere)")
                        .font(Island.caption)
                        .foregroundColor(Island.tertiary)
                }
                .buttonStyle(.plain)
                .help("Ask it in \(answerElsewhere) instead")
            }
            .frame(height: Metrics.captionRow)
            .padding(.top, 10)
        }
    }

    /// Where the question would otherwise be asked: the app that owns it
    /// (Conductor, for its own question tool) or the terminal.
    private var answerElsewhere: String {
        let tool = notification.toolName ?? ""
        let parts = tool.components(separatedBy: "__")
        return tool.hasPrefix("mcp__") && parts.count >= 3 ? parts[1].capitalized : "terminal"
    }

    private func choose(_ option: Int, in questions: [AgentQuestion]) {
        let index = min(questionIndex, questions.count - 1)
        if questions[index].multiSelect {
            var set = picked[index] ?? []
            if set.contains(option) { set.remove(option) } else { set.insert(option) }
            picked[index] = set
        } else {
            picked[index] = [option]
            advance(in: questions)
        }
    }

    /// Next question, or send every answer once the last one is in.
    private func advance(in questions: [AgentQuestion]) {
        if questionIndex + 1 < questions.count {
            withAnimation(Island.press) { questionIndex += 1 }
            return
        }
        var answers: [String: String] = [:]
        for (i, q) in questions.enumerated() {
            var labels = (picked[i] ?? []).sorted().map { q.options[$0].label }
            let own = (typed[i] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !own.isEmpty { labels.append(own) }
            guard !labels.isEmpty else { return }
            answers[q.question] = AgentQuestion.answer(labels)
        }
        onRespond?(.answer(answers))
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
                if characterState == .done, let session, !session.turnEdited.isEmpty || session.turnTests != nil {
                    TurnStats(edited: session.turnEdited.count, tests: session.turnTests)
                } else {
                    Text("just now")
                        .font(Island.numeric)
                        .foregroundColor(Island.tertiary)
                }
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
            if let session {
                Circle().fill(session.color).frame(width: 7, height: 7)
                    .padding(.trailing, -2)
            }
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
            // Just the word: the shortcut lives in the tooltip, not the label.
            Text(label)
                .font(Island.button)
                .lineLimit(1)
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

/// One answer to a question: its label, what it means, and (multi-select) a tick.
struct OptionRow: View {
    let option: AgentQuestion.Option
    let multiSelect: Bool
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if multiSelect {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(selected ? Island.primary : Island.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Island.primary)
                        .lineLimit(1)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: 11.5))
                            .foregroundColor(Island.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: NotchNotificationView.Metrics.optionHeight(option))
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : (hovered ? Island.controlHover : Island.control))
            )
            .contentShape(RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovered = $0 }
        .animation(Island.press, value: hovered)
        .animation(Island.press, value: selected)
        .help(option.description.isEmpty ? option.label : option.description)
        .accessibilityLabel(option.description.isEmpty ? option.label : "\(option.label), \(option.description)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What a finished turn did, at a glance: files it wrote, and how the last
/// test run went.
struct TurnStats: View {
    let edited: Int
    let tests: String?

    var body: some View {
        HStack(spacing: 10) {
            if edited > 0 {
                Text(edited == 1 ? "1 file" : "\(edited) files")
                    .font(Island.numeric)
                    .foregroundColor(Island.secondary)
            }
            if let tests {
                let passed = tests == "passed"
                HStack(spacing: 4) {
                    Image(systemName: passed ? "checkmark" : "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(passed ? "Tests pass" : "Tests fail")
                        .font(Island.numeric)
                }
                .foregroundColor(passed ? CharacterState.done.color : CharacterState.error.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Other": your own answer, typed. Return sends it.
struct OtherAnswerField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Island.tertiary)
            TextField("", text: $text, prompt: Text("Something else…").foregroundColor(Island.secondary.opacity(0.75)))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Island.primary)
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 12)
        .frame(height: NotchNotificationView.Metrics.otherHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                .fill(Island.well)
                .overlay(
                    RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
                        .strokeBorder(focused ? Color.white.opacity(0.28) : Island.hairline, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.windows.first { $0.isVisible && $0.canBecomeKey && $0 is NotchPanel }?.makeKey()
            focused = true
        }
        .accessibilityLabel("Type your own answer")
    }
}

