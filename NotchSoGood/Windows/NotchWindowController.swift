import AppKit
import SwiftUI

/// Observable data source so SwiftUI pill view updates without recreating the hosting view.
class PillDataSource: ObservableObject {
    @Published var sessions: [NotificationManager.SessionInfo] = []
    @Published var primaryStartTime: Date = Date()
    /// Whether the drop-down shows the runway footer. Decided by the controller
    /// in the same place it sizes the hover rect, so the two can't disagree.
    @Published var showsRunway = false
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
        // The approve/deny shortcuts exist only while there's something to answer.
        didSet { HotkeyManager.shared.setArmed(activePermissionRequestId != nil) }
    }
    /// The notification currently on screen, for re-laying out on display changes.
    private var activeNotification: NotchNotification?
    /// Exit-animation signal for the currently visible notification
    private var notificationPhase: NotificationPhase?

    // Permission queue — when multiple tools need approval simultaneously
    private var permissionQueue: [NotchNotification] = []
    private var permissionQueueMeta: [(sourceBundleId: String?, cwd: String?, sourcePid: pid_t?)] = []

    /// Screen each panel is currently built for. The pill bakes its notch
    /// dimensions into the SwiftUI view, so moving it to a display with
    /// different geometry means rebuilding it.
    private var pillGeometryKey: String?
    private var notificationScreen: NSScreen?

    // Pill sizing — shared with SessionPillView via PillLayout
    private let wingExpanded = PillLayout.wingExpanded
    private let wingCollapsed = PillLayout.wingCollapsed

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

    func hideSessionPill() {
        hasPillSession = false
        pillHoverMonitor.stop()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pillPanel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            // A session can start during the fade (`/clear` ends one and starts
            // the next): then the pill has been shown again and must stay.
            guard !self.hasPillSession else {
                self.pillPanel?.alphaValue = 1.0
                return
            }
            self.pillPanel?.orderOut(nil)
            self.pillPanel?.alphaValue = 1.0
        })
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
                let panelWidth = NotchNotificationView.Metrics.panelWidth(notchWidth: geo.notchWidth, hasNotch: geo.hasNotch)
                let contentHeight = NotchNotificationView.Metrics.contentHeight(for: activeNotification, panelWidth: panelWidth)
                let panelHeight = NotchNotificationView.Metrics.headerHeight(notchHeight: geo.barHeight, hasNotch: geo.hasNotch) + contentHeight
                let frame = calculateFrame(panelWidth: panelWidth, panelHeight: panelHeight, geo: geo)
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

        // Hide pill while notification is visible — set alpha directly (not animated)
        // to prevent a stale animation from overwriting alpha if refreshPill runs later.
        pillPanel?.alphaValue = 0
        pillPanel?.orderOut(nil)
        pillHoverMonitor.stop()

        guard let geo = resolveGeometry(screen) else { return }
        notificationScreen = NSScreen.screens.first { $0.frame == geo.screenFrame }
        let hasNotch = geo.hasNotch
        let notchH = geo.barHeight
        let notchW = geo.notchWidth

        // The card is sized to its content: a one-line command gets a shorter
        // card than a three-line one.
        let isPermission = notification.isInteractivePermission
        let panelWidth = NotchNotificationView.Metrics.panelWidth(notchWidth: notchW, hasNotch: hasNotch)
        let contentHeight = NotchNotificationView.Metrics.contentHeight(for: notification, panelWidth: panelWidth)
        let panelHeight = NotchNotificationView.Metrics.headerHeight(notchHeight: notchH, hasNotch: hasNotch) + contentHeight

        let frame = calculateFrame(panelWidth: panelWidth, panelHeight: panelHeight, geo: geo)

        if panel == nil {
            panel = NotchPanel(contentRect: frame)
            panel?.level = .popUpMenu + 1
            panel?.onCancel = { [weak self] in self?.cancelActive() }
        } else {
            panel?.setFrame(frame, display: true)
        }

        let resolvedBundleId = notification.sourceBundleId ?? sessionSourceBundleId
        let resolvedCwd = sessionCwd

        activePermissionRequestId = notification.permissionRequestId
        activeNotification = notification

        let phase = NotificationPhase()
        notificationPhase = phase

        let view = NotchNotificationView(
            notification: notification,
            hasNotch: hasNotch,
            notchWidth: notchW,
            notchHeight: notchH,
            onTap: { [weak self] in
                self?.dismiss()
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
            onApprove: isPermission ? { [weak self] in
                guard let reqId = self?.activePermissionRequestId else { return }
                PermissionServer.shared.respond(requestId: reqId, response: .allow)
                self?.activePermissionRequestId = nil
                self?.dismiss()
            } : nil,
            onAlwaysAllow: isPermission ? { [weak self] in
                guard let reqId = self?.activePermissionRequestId else { return }
                PermissionServer.shared.respond(requestId: reqId, response: .allowAlways)
                self?.activePermissionRequestId = nil
                self?.dismiss()
            } : nil,
            onDeny: isPermission ? { [weak self] in
                guard let reqId = self?.activePermissionRequestId else { return }
                PermissionServer.shared.respond(requestId: reqId, response: .deny)
                self?.activePermissionRequestId = nil
                self?.dismiss()
            } : nil,
            phase: phase,
            // Always called on the main thread (UI entry points only).
            session: MainActor.assumeIsolated {
                NotificationManager.shared.activeSessions.first { $0.id == notification.sessionId }
            }
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
        if !isPermission {
            scheduleAutoDismiss(after: Self.cardLifetime)
            notifHoverMonitor.onHoverChange = { [weak self] hovering in
                guard let self, !self.isDismissing, self.activePermissionRequestId == nil else { return }
                if hovering {
                    self.dismissTimer?.invalidate()
                    self.dismissTimer = nil
                } else {
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
    private static let lingerAfterHover: TimeInterval = 2.5

    private func scheduleAutoDismiss(after interval: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Show next queued permission notification (called after responding to current one)
    func showNextQueuedPermission() {
        guard !permissionQueue.isEmpty else { return }
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
        if let reqId = activePermissionRequestId {
            PermissionServer.shared.handOffToTerminal(requestId: reqId)
        } else {
            dismiss()
        }
    }

    /// Approve the currently visible permission request (global hotkey / UI).
    @MainActor func approveActivePermission() {
        guard let reqId = activePermissionRequestId else { return }
        PermissionServer.shared.respond(requestId: reqId, response: .allow)
        activePermissionRequestId = nil
        dismiss()
    }

    /// Deny the currently visible permission request (global hotkey / UI).
    @MainActor func denyActivePermission() {
        guard let reqId = activePermissionRequestId else { return }
        PermissionServer.shared.respond(requestId: reqId, response: .deny)
        activePermissionRequestId = nil
        dismiss()
    }

    /// True while an interactive permission is on screen (hotkeys only fire then).
    var hasActivePermission: Bool { activePermissionRequestId != nil }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
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

        // View-driven exit first — the island shrinks back into the notch —
        // then a short window fade catches whatever's left.
        notificationPhase?.dismissing = true
        notificationPhase = nil

        dismissGeneration &+= 1
        let generation = dismissGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            // A new notification took over the panel mid-dismiss — leave it alone.
            guard let self, self.dismissGeneration == generation else { return }
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
                Task { @MainActor [weak self] in
                    self?.restorePillIfNeeded()
                }
            })
        }
    }

    /// Restore the session pill after a notification dismisses, but only if sessions are still active.
    /// Uses NotificationManager as the source of truth instead of the local hasPillSession flag.
    @MainActor private func restorePillIfNeeded() {
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
