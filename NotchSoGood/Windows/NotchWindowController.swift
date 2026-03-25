import AppKit
import SwiftUI

/// Observable data source so SwiftUI pill view updates without recreating the hosting view.
class PillDataSource: ObservableObject {
    @Published var sessions: [NotificationManager.SessionInfo] = []
    @Published var primaryStartTime: Date = Date()
}

class NotchWindowController {
    private var panel: NotchPanel?
    private var pillPanel: NotchPanel?
    private var dismissTimer: Timer?
    private var isDismissing = false
    private var hasPillSession = false
    private let pillHoverMonitor = PillHoverMonitor()
    private let notifHoverMonitor = NotificationHoverMonitor()
    private let pillDataSource = PillDataSource()

    // Track current permission notification so we can dismiss it programmatically
    private var activePermissionRequestId: String?

    // Pill sizing constants (must match SessionPillView)
    private let wingExpanded: CGFloat = 110
    private let wingCollapsed: CGFloat = 56
    private let maxDropHeight: CGFloat = 160

    // MARK: - Session Pill

    func showSessionPill(sessions: [NotificationManager.SessionInfo], primaryStartTime: Date) {
        hasPillSession = true

        let hasNotch = NotchGeometry.hasNotch
        let geo = NotchGeometry.calculate()

        let notchW = geo?.notchWidth ?? 185
        let notchH = geo?.notchHeight ?? 32

        let maxWidth = notchW + (wingExpanded * 2)
        let maxHeight = notchH + 300

        let panelFrame = calculateFrame(panelWidth: maxWidth, panelHeight: maxHeight, hasNotch: hasNotch, geo: geo)

        let collapsedW = notchW + (wingCollapsed * 2)
        let expandedW = maxWidth
        let dropPad: CGFloat = 4 + 10
        let rowH: CGFloat = 36 * CGFloat(min(sessions.count, 6))
        let expandedH = notchH + dropPad + rowH
        let centerX = panelFrame.origin.x + maxWidth / 2

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

        pillDataSource.sessions = sessions
        pillDataSource.primaryStartTime = primaryStartTime

        if pillPanel == nil {
            pillPanel = NotchPanel(contentRect: panelFrame)
            pillPanel?.level = .statusBar + 1

            let pillView = SessionPillView(
                dataSource: pillDataSource,
                notchWidth: notchW,
                notchHeight: notchH,
                onTap: { [weak self] sessionId in
                    let session = self?.pillDataSource.sessions.first(where: { $0.id == sessionId })
                    TerminalLauncher.focusClaudeCode(sessionId: sessionId, sourceBundleId: session?.sourceBundleId, cwd: session?.cwd)
                },
                hoverMonitor: pillHoverMonitor
            )

            let container = VStack(spacing: 0) {
                pillView
                Spacer(minLength: 0)
            }
            .frame(width: maxWidth, height: maxHeight)

            let hostingView = NSHostingView(rootView: AnyView(container))
            hostingView.safeAreaRegions = []
            hostingView.layer?.backgroundColor = .clear
            pillPanel?.contentView = hostingView

        } else {
            pillPanel?.setFrame(panelFrame, display: true)
        }

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
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            pillPanel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.pillPanel?.orderOut(nil)
            self?.pillPanel?.alphaValue = 1.0
        })
    }

    var isShowingPill: Bool {
        pillPanel?.isVisible ?? false
    }

    // MARK: - Notification (transient expand + auto-dismiss)

    func showNotification(_ notification: NotchNotification, sessionSourceBundleId: String? = nil, sessionCwd: String? = nil) {
        dismissTimer?.invalidate()

        // Hide pill while notification is visible
        pillPanel?.animator().alphaValue = 0
        pillPanel?.orderOut(nil)
        pillHoverMonitor.stop()

        let hasNotch = NotchGeometry.hasNotch
        let geo = NotchGeometry.calculate()

        let notchH = geo?.notchHeight ?? 32
        let notchW = geo?.notchWidth ?? 185

        // Permission notifications are taller to fit buttons
        let isPermission = notification.isInteractivePermission
        let contentHeight: CGFloat = isPermission ? 130 : 76
        let panelWidth: CGFloat = hasNotch ? notchW + 200 : 380
        let panelHeight: CGFloat = hasNotch ? (notchH + contentHeight) : contentHeight

        let frame = calculateFrame(
            panelWidth: panelWidth,
            panelHeight: panelHeight,
            hasNotch: hasNotch,
            geo: geo
        )

        if panel == nil {
            panel = NotchPanel(contentRect: frame)
            panel?.level = .statusBar + 2
            panel?.onCancel = { [weak self] in self?.dismiss() }
        } else {
            panel?.setFrame(frame, display: true)
        }

        let resolvedBundleId = notification.sourceBundleId ?? sessionSourceBundleId
        let resolvedCwd = sessionCwd

        activePermissionRequestId = notification.permissionRequestId

        let view = NotchNotificationView(
            notification: notification,
            hasNotch: hasNotch,
            notchWidth: notchW,
            notchHeight: notchH,
            onTap: { [weak self] in
                self?.dismiss()
                TerminalLauncher.focusClaudeCode(sessionId: notification.sessionId, sourceBundleId: resolvedBundleId, cwd: resolvedCwd)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onApprove: isPermission ? { [weak self] in
                guard let reqId = self?.activePermissionRequestId else { return }
                PermissionServer.shared.respond(requestId: reqId, approve: true)
                self?.activePermissionRequestId = nil
                self?.dismiss()
            } : nil,
            onDeny: isPermission ? { [weak self] in
                guard let reqId = self?.activePermissionRequestId else { return }
                PermissionServer.shared.respond(requestId: reqId, approve: false)
                self?.activePermissionRequestId = nil
                self?.dismiss()
            } : nil
        )

        let hostingView = TransparentHostingView(rootView: AnyView(view))
        panel?.contentView = hostingView
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()

        // Hover monitor — content area below the notch
        notifHoverMonitor.contentScreenRect = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: contentHeight
        )
        if let panel {
            notifHoverMonitor.start(panel: panel)
        }

        SoundManager.shared.play(for: notification.type)

        // Auto-dismiss after 5s for regular notifications, NO auto-dismiss for permission
        if !isPermission {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        activePermissionRequestId = nil

        dismissTimer?.invalidate()
        dismissTimer = nil
        notifHoverMonitor.stop()

        guard let panel else {
            isDismissing = false
            return
        }

        // Fast exit
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1.0
            self?.isDismissing = false

            // Restore pill gracefully
            if let self, self.hasPillSession, let pillPanel = self.pillPanel {
                pillPanel.alphaValue = 0
                pillPanel.orderFrontRegardless()
                self.pillHoverMonitor.start(panel: pillPanel)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    pillPanel.animator().alphaValue = 1.0
                })
            }
        })
    }

    private func calculateFrame(panelWidth: CGFloat, panelHeight: CGFloat,
                                hasNotch: Bool, geo: NotchGeometry?) -> NSRect {
        if hasNotch, let geo = geo {
            let x = geo.centerX - panelWidth / 2
            let y = geo.screenTopY - panelHeight
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        } else {
            let fallback = NotchGeometry.fallbackOrigin()
            let x = fallback.x - panelWidth / 2
            let y = fallback.y - panelHeight
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        }
    }
}
