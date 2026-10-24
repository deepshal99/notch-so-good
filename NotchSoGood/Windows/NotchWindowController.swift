import AppKit
import SwiftUI

/// Observable data source so SwiftUI pill view updates without recreating the hosting view.
class PillDataSource: ObservableObject {
    @Published var sessions: [NotificationManager.SessionInfo] = []
    @Published var primaryStartTime: Date = Date()
    /// Whether the drop-down shows the runway footer. Decided by the controller
    /// in the same place it sizes the hover rect, so the two can't disagree.
    @Published var showsRunway = false
    /// Folded back into the notch (the last session ended). The view retracts;
    /// the controller orders the panel out once it has.
    @Published var retracted = false
}

class NotchWindowController {
    private var panel: NotchPanel?
    private var pillPanel: NotchPanel?
    private var dismissTimer: Timer?
    private var isDismissing = false
    /// Bumped whenever a dismiss starts or a new notification takes over the
    /// panel — lets the deferred dismiss completion detect it went stale.
    private var dismissGeneration = 0
    private var hasPillSession = false
    /// True while a notification is on screen — prevents refreshPill from fighting with the pill's hidden state.
    private var isNotificationActive = false
    private let pillHoverMonitor = PillHoverMonitor()
    private let notifHoverMonitor = NotificationHoverMonitor()
    private let pillDataSource = PillDataSource()

    // Track current permission notification so we can dismiss it programmatically
    private var activePermissionRequestId: String? {
        // The shortcuts exist only while there's something to use them on.
        didSet { armHotkeys() }
    }
    /// The notification currently on screen, for re-laying out on display changes.
    private var activeNotification: NotchNotification? {
        didSet { armHotkeys() }
    }
    /// Where the card on screen came from, for jumping there or cycling cards.
    private var activeMeta: (sourceBundleId: String?, cwd: String?, sourcePid: pid_t?) = (nil, nil, nil)
    /// Exit-animation signal for the currently visible notification
    private var notificationPhase: NotificationPhase?

    // Permission queue — when multiple tools need approval simultaneously
    private var permissionQueue: [NotchNotification] = [] {
        didSet { publishDeck() }
    }
    /// The queue as the card on screen shows it, under itself.
    private let deck = WaitingDeck()
    private var permissionQueueMeta: [(sourceBundleId: String?, cwd: String?, sourcePid: pid_t?)] = []
    /// Finished / error / heads-up cards that arrived while a waiting card was
    /// up: shown once it's answered, newest few only, instead of being lost.
    private var heldCards: [(notification: NotchNotification, meta: (sourceBundleId: String?, cwd: String?, sourcePid: pid_t?))] = []
    /// When the current waiting card appeared. Hotkeys ignore its first half
    /// second, so a double press never answers a card you haven't seen.
    private var waitingShownAt = Date.distantPast
    /// A reply (or other answer) is being typed on the card: it stays up.
    private var cardBeingTyped = false

    /// Screen each panel is currently built for. The pill bakes its notch
    /// dimensions into the SwiftUI view, so moving it to a display with
    /// different geometry means rebuilding it.
    private var pillGeometryKey: String?
    private var notificationScreen: NSScreen?

    // Pill sizing — shared with SessionPillView via PillLayout
    private let wingExpanded = PillLayout.wingExpanded
    private let wingCollapsed = PillLayout.wingCollapsed

    init() {
        deck.onPick = { [weak self] requestId in
            MainActor.assumeIsolated { self?.bringForward(requestId) }
        }
    }

    // MARK: - Session Pill

    func showSessionPill(
        sessions: [NotificationManager.SessionInfo],
        primaryStartTime: Date,
        screen: NSScreen? = nil
    ) {
        hasPillSession = true

        guard let geo = resolveGeometry(screen) else { return }
        let notchW = geo.notchWidth
        let notchH = geo.barHeight

        let maxWidth = notchW + (wingExpanded * 2)
        let maxHeight = notchH + PillLayout.maxContentHeight

        let panelFrame = calculateFrame(panelWidth: maxWidth, panelHeight: maxHeight, geo: geo)

        // Rebuild when the target display's geometry differs from what's built.
        let geometryKey = "\(geo.displayID)-\(notchW)-\(notchH)"
        if pillGeometryKey != geometryKey, pillPanel != nil {
            pillHoverMonitor.stop()
            pillPanel?.orderOut(nil)
            pillPanel = nil
        }
        pillGeometryKey = geometryKey

        let collapsedW = notchW + (wingCollapsed * 2)
        let expandedW = maxWidth
        let centerX = panelFrame.origin.x + maxWidth / 2

        // Always called on the main thread (UI entry points only).
        let showsRunway = MainActor.assumeIsolated {
            UsageLimitsStore.shared.sessionWindow(for: sessions.first?.agentSource ?? .claude) != nil
        }
        let expandedH = PillLayout.expandedHeight(for: sessions, notchHeight: notchH, runway: showsRunway)
        pillScreen = geo.screenFrame

        pillHoverMonitor.collapsedScreenRect = NSRect(
            x: centerX - collapsedW / 2,
            y: panelFrame.maxY - notchH,
            width: collapsedW,
            height: notchH
        )
        pillHoverMonitor.expandedScreenRect = NSRect(
            x: centerX - expandedW / 2,
            y: panelFrame.maxY - expandedH,
            width: expandedW,
            height: expandedH
        )

        // A session started while the pill was folding away (or after): out it comes again.
        if pillDataSource.retracted { pillDataSource.retracted = false }

        // Only publish real changes: every hook event lands here, and each
        // assignment re-renders the pill.
        if pillDataSource.sessions != sessions { pillDataSource.sessions = sessions }
        if pillDataSource.primaryStartTime != primaryStartTime { pillDataSource.primaryStartTime = primaryStartTime }
        if pillDataSource.showsRunway != showsRunway { pillDataSource.showsRunway = showsRunway }

        if pillPanel == nil {
            pillPanel = NotchPanel(contentRect: panelFrame)
            pillPanel?.level = .popUpMenu

            let pillView = SessionPillView(
                dataSource: pillDataSource,
                notchWidth: notchW,
                notchHeight: notchH,
                hasNotch: geo.hasNotch,
                onTap: { [weak self] sessionId in
                    let session = self?.pillDataSource.sessions.first(where: { $0.id == sessionId })
                    TerminalLauncher.focusClaudeCode(
                        sessionId: sessionId,
                        sourceBundleId: session?.sourceBundleId,
                        cwd: session?.cwd,
                        sourcePid: session?.sourcePid
                    )
                },
                hoverMonitor: pillHoverMonitor
            )

            let container = VStack(spacing: 0) {
                pillView
                Spacer(minLength: 0)
            }
            .frame(width: maxWidth, height: maxHeight)

            let hostingView = TransparentHostingView(rootView: AnyView(container))
            hostingView.safeAreaRegions = []
            pillPanel?.contentView = hostingView

        } else {
            if pillPanel?.frame != panelFrame { pillPanel?.setFrame(panelFrame, display: true) }
        }

        // Don't show/restore the pill while a notification is on screen —
        // the notification owns the notch area and dismiss() will restore the pill.
        guard !isNotificationActive else { return }
        // No menu bar (fullscreen space) — nothing to blend into, stay hidden.
        guard !isMenuBarHidden else { return }

        guard let pillPanel else { return }
        if !pillPanel.isVisible {
            pillPanel.alphaValue = 1.0
            pillPanel.orderFrontRegardless()
        }

        pillHoverMonitor.start(panel: pillPanel)
    }

    /// The "Hide from screen sharing" setting, applied to the open panels.
    func applyCaptureVisibility() {
        let type: NSWindow.SharingType = NotificationManager.hiddenFromCapture ? .none : .readOnly
        panel?.sharingType = type
        pillPanel?.sharingType = type
    }

    func hideSessionPill() {
        hasPillSession = false
        pillHoverMonitor.stop()

        // The view folds the wings back into the notch, the way they came out;
        // then the panel goes.
        pillDataSource.retracted = true
        pillHideGeneration &+= 1
        let generation = pillHideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            // A session can start meanwhile (`/clear` ends one and starts the
            // next): then the pill has come back out and must stay.
            guard let self, !self.hasPillSession, self.pillHideGeneration == generation else { return }
            self.pillPanel?.orderOut(nil)
        }
    }

    private var pillHideGeneration = 0

    /// The pill as a card meets it, on the display the card is on: open if
    /// you're hovering it, else collapsed. Nil when it's elsewhere or unbuilt.
    private func pillFrame(on screenFrame: NSRect, open: Bool) -> NotchNotificationView.PillFrame? {
        guard pillPanel != nil, pillScreen == screenFrame,
              let geo = resolveGeometry(NSScreen.screens.first { $0.frame == screenFrame }) else { return nil }
        // Mirrors SessionPillView's shape and character placement.
        let rect = open ? pillHoverMonitor.expandedScreenRect : pillHoverMonitor.collapsedScreenRect
        let wall: CGFloat = geo.hasNotch ? (open ? 9 : 6) : 0
        return NotchNotificationView.PillFrame(
            size: rect.size,
            topRadius: wall,
            bottomRadius: open ? 24 : geo.barHeight / 2,
            characterX: open ? wall + Island.contentInset - 17 : 0
        )
    }

    var isShowingPill: Bool {
        pillPanel?.isVisible ?? false
    }

    /// True when the notch screen's menu bar is hidden (fullscreen space):
    /// there's no black backdrop to blend into, so the pill would float as a
    /// blob over the app's own UI.
    private var isMenuBarHidden: Bool {
        // Check the display the pill is actually on, not always the built-in one.
        let target = pillScreen.flatMap { frame in
            NSScreen.screens.first { $0.frame == frame }
        }
        guard let screen = target ?? NotchGeometry.notchScreen ?? NSScreen.main else { return false }
        return screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }

    /// Frame of the display the pill was last built for.
    private var pillScreen: NSRect?

    /// Geometry for an explicit screen, or the notch screen when we have no idea.
    private func resolveGeometry(_ screen: NSScreen?) -> NotchGeometry? {
        if let screen { return NotchGeometry.geometry(for: screen) }
        return NotchGeometry.calculate()
    }

    /// Space changed (fullscreen in/out, desktop switch) — hide or restore the pill.
    @MainActor func handleSpaceChange() {
        if isMenuBarHidden {
            pillHoverMonitor.stop()
            pillPanel?.orderOut(nil)
        } else if !isNotificationActive {
            restorePillIfNeeded()
        }
    }

    /// Rebuild/reposition panels after display configuration changes
    /// (monitor plugged/unplugged, resolution change — notch geometry may differ).
    @MainActor func handleScreenChange() {
        let manager = NotificationManager.shared
        // Displays moved: every cached "which screen is this session on" answer
        // is stale, including the one the visible notification used.
        manager.invalidateDisplayCache()

        // Reposition an on-screen notification (permission dialogs persist indefinitely)
        if isNotificationActive, let panel, let activeNotification {
            let stillAttached = notificationScreen.flatMap { screen in
                NSScreen.screens.first { $0.displayID == screen.displayID }
            }
            if let geo = resolveGeometry(stillAttached) {
                let frame = cardFrame(for: activeNotification, geo: geo)
                panel.setFrame(frame, display: true)
                notifHoverMonitor.contentScreenRect = frame
            }
        }

        // Rebuild the pill — its notch dimensions are baked into the SwiftUI view
        pillHoverMonitor.stop()
        pillPanel?.orderOut(nil)
        pillPanel = nil
        pillGeometryKey = nil

        if manager.hasActiveSession, manager.showSessionPill, let primary = manager.primarySession {
            showSessionPill(
                sessions: manager.orderedSessions,
                primaryStartTime: primary.startTime,
                screen: manager.targetScreen(for: primary)
            )
        }
    }

    // MARK: - Notification (transient expand + auto-dismiss)

    func showNotification(
        _ notification: NotchNotification,
        sessionSourceBundleId: String? = nil,
        sessionCwd: String? = nil,
        sessionSourcePid: pid_t? = nil,
        screen: NSScreen? = nil
    ) {
        // A waiting permission owns the island until it's answered: a nudge, a
        // "finished" from another session or a usage heads-up must never replace
        // it (that used to strand the request with no buttons and no hotkeys).
        if activePermissionRequestId != nil && !notification.isInteractivePermission {
            heldCards.append((notification, (sessionSourceBundleId, sessionCwd, sessionSourcePid)))
            if heldCards.count > 3 { heldCards.removeFirst(heldCards.count - 3) }
            return
        }

        // Queue concurrent permission requests instead of replacing
        if notification.isInteractivePermission && activePermissionRequestId != nil {
            permissionQueue.append(notification)
            permissionQueueMeta.append((
                sourceBundleId: sessionSourceBundleId,
                cwd: sessionCwd,
                sourcePid: sessionSourcePid
            ))
            return
        }

        dismissTimer?.invalidate()
        isNotificationActive = true
        // This notification takes over the panel — invalidate any in-flight
        // dismiss so its deferred fade can't order out the new content.
        dismissGeneration &+= 1
        isDismissing = false

        guard let geo = resolveGeometry(screen) else { return }

        // On screen, the pill is what the card opens out of.
        let fromPill = (pillPanel?.isVisible == true && pillPanel?.alphaValue ?? 0 > 0 && !pillDataSource.retracted)
            ? pillFrame(on: geo.screenFrame, open: pillHoverMonitor.isHovered) : nil

        // Hide pill while notification is visible — set alpha directly (not animated)
        // to prevent a stale animation from overwriting alpha if refreshPill runs later.
        pillPanel?.alphaValue = 0
        pillPanel?.orderOut(nil)
        pillHoverMonitor.stop()

        notificationScreen = NSScreen.screens.first { $0.frame == geo.screenFrame }
        let hasNotch = geo.hasNotch
        let notchH = geo.barHeight
        let notchW = geo.notchWidth

        let isPermission = notification.isInteractivePermission
        let frame = cardFrame(for: notification, geo: geo)

        if panel == nil {
            panel = NotchPanel(contentRect: frame)
            panel?.level = .popUpMenu + 1
            panel?.onCancel = { [weak self] in self?.cancelActive() }
        } else {
            panel?.setFrame(frame, display: true)
        }

        if case .question = notification.interaction { panel?.acceptsTyping = true } else { panel?.acceptsTyping = notification.canReply }
        // Over a full-screen video or slides, only a card that needs an answer
        // shows; over the full-screen app your agents run in, everything does.
        panel?.showsOverFullScreen = isPermission || TerminalLauncher.frontmostRunsAgents(
            sessionPids: MainActor.assumeIsolated { NotificationManager.shared.activeSessions.compactMap(\.sourcePid) })
        let resolvedBundleId = notification.sourceBundleId ?? sessionSourceBundleId
        let resolvedCwd = sessionCwd

        questionIndex = 0
        activePermissionRequestId = notification.permissionRequestId
        activeMeta = (resolvedBundleId, resolvedCwd, sessionSourcePid)
        activeNotification = notification
        if isPermission { waitingShownAt = Date() }

        let phase = NotificationPhase()
        notificationPhase = phase

        let view = NotchNotificationView(
            notification: notification,
            hasNotch: hasNotch,
            notchWidth: notchW,
            notchHeight: notchH,
            onTap: { [weak self] in
                self?.dismiss()
                if notification.title == NotchNotification.updateTitle {
                    Task { @MainActor in Updates.shared.installAndRestart() }
                    return
                }
                Task { @MainActor in
                    NotificationManager.shared.muteRepeats(sessionId: notification.sessionId, type: notification.type)
                }
                TerminalLauncher.focusClaudeCode(
                    sessionId: notification.sessionId,
                    sourceBundleId: resolvedBundleId,
                    cwd: resolvedCwd,
                    sourcePid: sessionSourcePid
                )
            },
            onDismiss: { [weak self] in
                self?.dismiss()
                Task { @MainActor in
                    NotificationManager.shared.muteRepeats(sessionId: notification.sessionId, type: notification.type)
                }
            },
            onRespond: isPermission ? { [weak self] response in
                guard let self, let reqId = self.activePermissionRequestId else { return }
                self.answer(reqId, response, focus: (notification.sessionId, resolvedBundleId, resolvedCwd, sessionSourcePid))
            } : nil,
            onReply: notification.canReply ? { [weak self] text in
                guard let sid = notification.sessionId else { return }
                if notification.tour != nil {
                    self?.dismiss()
                    MainActor.assumeIsolated { Tour.shared.replied(text) }
                    return
                }
                MainActor.assumeIsolated { Replies.shared.send(text, to: sid) { sent in
                    if sent {
                        NotificationManager.shared.updateSessionStatus(sessionId: sid, status: .running)
                        self?.dismiss()
                    } else {
                        // Not listening any more (it timed out, or you typed in the
                        // terminal): take you there instead.
                        self?.dismiss()
                        TerminalLauncher.focusClaudeCode(sessionId: sid, sourceBundleId: resolvedBundleId,
                                                         cwd: resolvedCwd, sourcePid: sessionSourcePid)
                    }
                } }
            } : nil,
            onTyping: { [weak self] typing in
                guard let self, self.activePermissionRequestId == nil else { return }
                self.cardBeingTyped = typing
                if typing { self.dismissTimer?.invalidate(); self.dismissTimer = nil }
                else if !self.notifHoverMonitor.inside { self.scheduleAutoDismiss(after: Self.lingerAfterHover) }
            },
            onQuestionShown: { [weak self] index in self?.questionShown(index) },
            onTourNext: { [weak self] in
                self?.dismiss()
                MainActor.assumeIsolated { Tour.shared.next() }
            },
            onTourSkip: { MainActor.assumeIsolated { Tour.shared.skip() } },
            phase: phase,
            deck: deck,
            // Always called on the main thread (UI entry points only).
            session: MainActor.assumeIsolated {
                NotificationManager.shared.activeSessions.first { $0.id == notification.sessionId }
            },
            fromPill: fromPill
        )

        let hostingView = TransparentHostingView(rootView: AnyView(view))
        panel?.contentView = hostingView
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()

        // Hover monitor — the whole island (its top strip sits beside the notch)
        notifHoverMonitor.contentScreenRect = frame
        if let panel {
            notifHoverMonitor.start(panel: panel)
        }

        SoundManager.shared.play(for: notification.type)

        // Regular cards leave on their own; a card you're reading stays until
        // you move away (then it gives you a moment). Permissions never time out here.
        // Practice cards wait for you, except the last.
        let tourWaits = notification.tour.map { $0.index < $0.total - 1 } ?? false
        if !isPermission && !tourWaits {
            scheduleAutoDismiss(after: notification.canReply ? Self.replyCardLifetime : Self.cardLifetime)
            notifHoverMonitor.onHoverChange = { [weak self] hovering in
                guard let self, !self.isDismissing, self.activePermissionRequestId == nil else { return }
                if hovering {
                    self.dismissTimer?.invalidate()
                    self.dismissTimer = nil
                } else if !self.cardBeingTyped {
                    self.scheduleAutoDismiss(after: Self.lingerAfterHover)
                }
            }
            // Already under the pointer when it appeared: hold it from the start.
            if notifHoverMonitor.inside {
                dismissTimer?.invalidate()
                dismissTimer = nil
            }
        } else {
            notifHoverMonitor.onHoverChange = nil
        }
    }

    private static let cardLifetime: TimeInterval = 6
    /// Long enough to decide whether to answer it.
    private static let replyCardLifetime: TimeInterval = 10
    private static let lingerAfterHover: TimeInterval = 2.5

    private func scheduleAutoDismiss(after interval: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Send the user's answer. Handing back to the terminal also brings the
    /// terminal forward, since that's where the answer happens now.
    private func answer(_ reqId: String, _ response: CardResponse,
                        focus: (sessionId: String?, bundleId: String?, cwd: String?, pid: pid_t?)? = nil) {
        activePermissionRequestId = nil
        if reqId.hasPrefix("tour-") {
            // Practice: nothing is waiting on it but the tour.
            dismiss()
            MainActor.assumeIsolated { if response == .handOff { Tour.shared.skip() } else { Tour.shared.answered(response) } }
            return
        }
        if response == .handOff {
            PermissionServer.shared.handOffToTerminal(requestId: reqId)
            if let focus {
                TerminalLauncher.focusClaudeCode(sessionId: focus.sessionId, sourceBundleId: focus.bundleId,
                                                 cwd: focus.cwd, sourcePid: focus.pid)
            }
        } else {
            PermissionServer.shared.respond(requestId: reqId, response: response)
        }
        dismiss()
        // respond() moves the queue on; a hand-back has to do it here, or the
        // next waiting card (and any held ones) would never show.
        if response == .handOff {
            DispatchQueue.main.async { [weak self] in self?.showNextQueuedPermission() }
        }
    }

    /// Show next queued permission notification (called after responding to current one)
    func showNextQueuedPermission() {
        guard !permissionQueue.isEmpty else {
            // Nothing else waiting: show what arrived meanwhile (the latest only;
            // older ones are already stale).
            if activePermissionRequestId == nil, let held = heldCards.popLast() {
                heldCards.removeAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, self.activePermissionRequestId == nil else { return }
                    self.showNotification(held.notification, sessionSourceBundleId: held.meta.sourceBundleId,
                                          sessionCwd: held.meta.cwd, sessionSourcePid: held.meta.sourcePid)
                }
            }
            return
        }
        let next = permissionQueue.removeFirst()
        let meta = permissionQueueMeta.removeFirst()
        showNotification(
            next,
            sessionSourceBundleId: meta.sourceBundleId,
            sessionCwd: meta.cwd,
            sessionSourcePid: meta.sourcePid
        )
    }

    /// Dismiss a specific permission by request ID (e.g. on timeout)
    func dismissPermission(requestId: String) {
        // Remove from queue if it hasn't been shown yet
        if let idx = permissionQueue.firstIndex(where: { $0.permissionRequestId == requestId }) {
            permissionQueue.remove(at: idx)
            permissionQueueMeta.remove(at: idx)
            return
        }
        // If it's the active one, dismiss it and move on to the next in line
        if activePermissionRequestId == requestId {
            dismiss()
            DispatchQueue.main.async { [weak self] in self?.showNextQueuedPermission() }
        }
    }

    /// Esc: a permission card hands the decision back to the terminal (Claude
    /// Code's own prompt) instead of leaving the request hanging; anything else
    /// just closes.
    private func cancelActive() {
        if activeNotification?.tour != nil {
            MainActor.assumeIsolated { Tour.shared.skip() }
        } else if let reqId = activePermissionRequestId {
            PermissionServer.shared.handOffToTerminal(requestId: reqId)
        } else {
            dismiss()
        }
    }

    /// Approve the currently visible permission request (global hotkey / UI).
    @MainActor func approveActivePermission() {
        guard let reqId = activePermissionRequestId, Date().timeIntervalSince(waitingShownAt) > 0.5 else { return }
        switch activeNotification?.interaction {
        case .plan: answer(reqId, .approvePlan(acceptEdits: false))
        case .question: return          // an answer needs a choice, not a shortcut
        default: answer(reqId, .allow)
        }
    }

    /// Deny the currently visible permission request (global hotkey / UI).
    @MainActor func denyActivePermission() {
        guard let reqId = activePermissionRequestId, Date().timeIntervalSince(waitingShownAt) > 0.5 else { return }
        switch activeNotification?.interaction {
        case .plan, .question: answer(reqId, .handOff)
        default: answer(reqId, .deny)
        }
    }

    /// The tour is over (skipped, or a real card needs the notch): its card goes.
    func endTour() {
        let queued = permissionQueue.indices.filter { permissionQueue[$0].tour != nil }.reversed()
        for i in queued { permissionQueue.remove(at: i); permissionQueueMeta.remove(at: i) }
        if activeNotification?.tour != nil {
            activePermissionRequestId = nil
            dismiss()
        }
    }

    /// True while an interactive permission is on screen (hotkeys only fire then).
    var hasActivePermission: Bool { activePermissionRequestId != nil }

    /// The keys the card on screen can use.
    private func armHotkeys() {
        var keys: Set<HotkeyManager.Key> = []
        if let notification = activeNotification {
            if activePermissionRequestId != nil {
                keys.formUnion([.deny, .next, .open])
                switch notification.interaction {
                case .question(let questions):
                    let index = min(questionIndex, max(questions.count - 1, 0))
                    keys.insert(.reply)
                    if questions.indices.contains(index) {
                        keys.formUnion(HotkeyManager.Key.options(questions[index].options.count))
                    }
                case .permission(let always):
                    keys.insert(.allow)
                    if always != nil { keys.insert(.session) }
                default:
                    keys.insert(.allow)
                }
            } else if notification.sessionId != nil {
                keys.insert(.open)
                if notification.canReply { keys.insert(.reply) }
            }
        }
        HotkeyManager.shared.arm(keys)
    }

    /// Which question of a multi-question card is showing (the card reports it),
    /// so ⌃⌥1–6 match its options.
    private var questionIndex = 0 {
        didSet { if questionIndex != oldValue { armHotkeys() } }
    }

    func questionShown(_ index: Int) { questionIndex = index }

    private var hotkeyReady: Bool { Date().timeIntervalSince(waitingShownAt) > 0.5 }

    /// ⌃⌥S: allow, and keep allowing the same thing until the session ends.
    @MainActor func allowActiveForSession() {
        guard let reqId = activePermissionRequestId, hotkeyReady,
              case .permission(let always)? = activeNotification?.interaction, always != nil else { return }
        answer(reqId, .allowSession)
    }

    /// ⌃⌥1–6: the option with that number on a question card.
    @MainActor func pickOption(_ offset: Int) {
        guard activePermissionRequestId != nil, hotkeyReady,
              case .question? = activeNotification?.interaction else { return }
        NotificationCenter.default.post(name: .notchPickOption, object: offset)
    }

    /// ⌃⌥N: put this waiting card at the back of the line and show the next.
    @MainActor func showNextWaitingCard() {
        guard activePermissionRequestId != nil, hotkeyReady, !permissionQueue.isEmpty,
              let current = activeNotification else { return }
        permissionQueue.append(current)
        permissionQueueMeta.append(activeMeta)
        activePermissionRequestId = nil
        showNextQueuedPermission()
    }

    /// A card in the deck was clicked: it comes forward, and the one on screen
    /// goes back in line, next up.
    @MainActor func bringForward(_ requestId: String) {
        guard activePermissionRequestId != nil, let current = activeNotification,
              let index = permissionQueue.firstIndex(where: { $0.permissionRequestId == requestId }) else { return }
        let picked = permissionQueue[index], meta = permissionQueueMeta[index]
        permissionQueueMeta.remove(at: index)
        permissionQueueMeta.insert(activeMeta, at: 0)
        var queue = permissionQueue
        queue.remove(at: index)
        queue.insert(current, at: 0)
        permissionQueue = queue
        activePermissionRequestId = nil
        showNotification(picked, sessionSourceBundleId: meta.sourceBundleId, sessionCwd: meta.cwd, sessionSourcePid: meta.sourcePid)
    }

    /// The queue changed: the deck under the card on screen follows, and the
    /// card grows or shrinks to fit it.
    private func publishDeck() {
        let entries = MainActor.assumeIsolated {
            let sessions = NotificationManager.shared.activeSessions
            return permissionQueue.compactMap { n -> WaitingDeck.Entry? in
                guard let id = n.permissionRequestId else { return nil }
                return Self.deckEntry(id: id, notification: n, session: sessions.first { $0.id == n.sessionId })
            }
        }
        guard entries != deck.entries else { return }
        deck.entries = entries
        guard isNotificationActive, !isDismissing, let panel, let activeNotification,
              activeNotification.isInteractivePermission else { return }
        let screen = notificationScreen.flatMap { s in NSScreen.screens.first { $0.displayID == s.displayID } }
        guard let geo = resolveGeometry(screen) else { return }
        let frame = cardFrame(for: activeNotification, geo: geo)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        notifHoverMonitor.contentScreenRect = frame
    }

    static func deckEntry(id: String, notification: NotchNotification, session: NotificationManager.SessionInfo?) -> WaitingDeck.Entry {
        let kind: String
        switch notification.interaction {
        case .plan: kind = "Plan"
        case .question: kind = "Question"
        default: kind = notification.toolName.map { SessionStatus.mcpServer($0) ?? $0 } ?? "Approval"
        }
        // The last part of "parent / project": Conductor's workspace, or the folder.
        let name = session.map { $0.projectName.components(separatedBy: " / ").last ?? $0.projectName } ?? "Claude Code"
        return WaitingDeck.Entry(id: id, agent: session?.agentSource ?? .claude, name: name, kind: kind, since: notification.timestamp)
    }

    /// ⌃⌥O: go to where the session runs. A waiting card is handed back there,
    /// so the agent asks in its own prompt.
    @MainActor func openActiveCard() {
        guard let notification = activeNotification else { return }
        let meta = activeMeta
        if let reqId = activePermissionRequestId {
            guard hotkeyReady else { return }
            answer(reqId, .handOff, focus: (notification.sessionId, meta.sourceBundleId, meta.cwd, meta.sourcePid))
        } else {
            dismiss()
            TerminalLauncher.focusClaudeCode(sessionId: notification.sessionId, sourceBundleId: meta.sourceBundleId,
                                             cwd: meta.cwd, sourcePid: meta.sourcePid)
        }
    }

    /// ⌃⌥R: the caret in the card's field (a reply, or your own answer). A
    /// panel only gets keys from an app in front, so the app comes forward
    /// this once, and hands focus back when the card goes.
    @MainActor func focusCardField() {
        guard activeNotification != nil, let panel, panel.acceptsTyping else { return }
        if !NSApp.isActive {
            appBeforeTyping = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .notchFocusField, object: nil)
        }
    }

    /// The app you were in before ⌃⌥R brought the card forward.
    private var appBeforeTyping: NSRunningApplication?

    private func restoreFocus() {
        guard let app = appBeforeTyping else { return }
        appBeforeTyping = nil
        app.activate()
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        cardBeingTyped = false
        restoreFocus()
        activePermissionRequestId = nil
        activeNotification = nil

        dismissTimer?.invalidate()
        dismissTimer = nil
        notifHoverMonitor.stop()

        guard let panel else {
            isDismissing = false
            isNotificationActive = false
            Task { @MainActor in self.restorePillIfNeeded() }
            return
        }

        // When the pill is coming back, the card folds into its exact shape and
        // the pill takes over underneath; otherwise it goes back into the notch.
        let intoPill = MainActor.assumeIsolated { willRestorePill }
            ? notificationScreen.flatMap { pillFrame(on: $0.frame, open: false) } : nil

        // View-driven exit first — the island shrinks back into the pill or the
        // notch — then a short window fade catches whatever's left.
        notificationPhase?.intoPill = intoPill
        notificationPhase?.dismissing = true
        notificationPhase = nil

        dismissGeneration &+= 1
        let generation = dismissGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            // A new notification took over the panel mid-dismiss — leave it alone.
            guard let self, self.dismissGeneration == generation else { return }
            // The card is the pill's shape now: put the pill under it, whole, so
            // only the character's pose crossfades as the card goes.
            if intoPill != nil { MainActor.assumeIsolated { self.restorePillIfNeeded(underCard: true) } }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self else { return }
                guard self.dismissGeneration == generation else {
                    // Takeover happened mid-fade: the new notification owns the
                    // panel — just make sure it's visible again.
                    if self.isNotificationActive { self.panel?.alphaValue = 1.0 }
                    return
                }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1.0
                self.isDismissing = false
                self.isNotificationActive = false
                // Already out under the card (unless something stopped it).
                if intoPill != nil, self.pillPanel?.isVisible == true { return }
                Task { @MainActor [weak self] in
                    self?.restorePillIfNeeded()
                }
            })
        }
    }

    /// Whether the pill comes back once the card on screen goes.
    @MainActor private var willRestorePill: Bool {
        let manager = NotificationManager.shared
        return manager.hasActiveSession && manager.showSessionPill && !isMenuBarHidden && pillPanel != nil
    }

    /// Restore the session pill after a notification dismisses, but only if sessions are still active.
    /// Uses NotificationManager as the source of truth instead of the local hasPillSession flag.
    /// Under a card that has folded into its shape it appears whole, with no fade.
    @MainActor private func restorePillIfNeeded(underCard: Bool = false) {
        let manager = NotificationManager.shared
        guard manager.hasActiveSession, manager.showSessionPill else {
            if hasPillSession {
                hideSessionPill()
            }
            return
        }

        guard !isMenuBarHidden else { return }

        // Sessions are active — restore the pill panel
        if let pillPanel {
            hasPillSession = true
            if pillDataSource.retracted { pillDataSource.retracted = false }
            if underCard {
                pillPanel.alphaValue = 1.0
                pillPanel.orderFrontRegardless()
                pillHoverMonitor.start(panel: pillPanel)
                return
            }
            pillPanel.alphaValue = 0
            pillPanel.orderFrontRegardless()
            pillHoverMonitor.start(panel: pillPanel)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                pillPanel.animator().alphaValue = 1.0
            })
        } else {
            // Pill panel was never created — rebuild from current session state
            if let primary = manager.primarySession {
                showSessionPill(
                    sessions: manager.orderedSessions,
                    primaryStartTime: primary.startTime,
                    screen: manager.targetScreen(for: primary)
                )
            }
        }
    }

    /// A card's panel, sized to its content (a one-line command gets a shorter
    /// card than a three-line one) and, under a waiting card, the deck.
    private func cardFrame(for notification: NotchNotification, geo: NotchGeometry) -> NSRect {
        let panelWidth = NotchNotificationView.Metrics.panelWidth(notchWidth: geo.notchWidth, hasNotch: geo.hasNotch)
        let waiting = notification.isInteractivePermission ? deck.entries.count : 0
        let contentHeight = NotchNotificationView.Metrics.contentHeight(for: notification, panelWidth: panelWidth, waiting: waiting)
        let panelHeight = NotchNotificationView.Metrics.headerHeight(notchHeight: geo.barHeight, hasNotch: geo.hasNotch) + contentHeight
        return calculateFrame(panelWidth: panelWidth, panelHeight: panelHeight, geo: geo)
    }

    /// Centre horizontally on the target display and hang down from its top —
    /// the screen's edge on a notched display, just under the menu bar elsewhere.
    private func calculateFrame(panelWidth: CGFloat, panelHeight: CGFloat,
                                geo: NotchGeometry) -> NSRect {
        NSRect(
            x: geo.centerX - panelWidth / 2,
            y: geo.topY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )
    }
}
