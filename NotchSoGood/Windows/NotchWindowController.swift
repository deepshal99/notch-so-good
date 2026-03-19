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

        // Panel stays at max size for smooth SwiftUI animations
        // Must match SessionPillView's maxWidth/maxHeight
        let maxWidth = notchW + (wingExpanded * 2)
        let maxHeight = notchH + 300  // Match SessionPillView.maxContentHeight

        let panelFrame = calculateFrame(panelWidth: maxWidth, panelHeight: maxHeight, hasNotch: hasNotch, geo: geo)

        // Compute pill screen rects for hover detection
        let collapsedW = notchW + (wingCollapsed * 2)
        let expandedW = maxWidth
        // Estimate expanded content height based on session count (matches SessionPillView row sizing)
        let dropPad: CGFloat = 4 + 10  // top + bottom padding
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

        // Update data source — SwiftUI observes changes without recreating the view
        pillDataSource.sessions = sessions
        pillDataSource.primaryStartTime = primaryStartTime

        if pillPanel == nil {
            pillPanel = NotchPanel(contentRect: panelFrame)
            pillPanel?.level = .statusBar + 1

            let pillView = SessionPillView(
                dataSource: pillDataSource,
                notchWidth: notchW,
                notchHeight: notchH,
                onTap: { sessionId in
                    TerminalLauncher.focusClaudeCode(sessionId: sessionId, sourceBundleId: nil)
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

    func showNotification(_ notification: NotchNotification) {
        dismissTimer?.invalidate()

        // Hide pill while notification is visible (cancel any in-progress fade animation)
        pillPanel?.animator().alphaValue = 0
        pillPanel?.orderOut(nil)
        pillHoverMonitor.stop()

        let hasNotch = NotchGeometry.hasNotch
        let geo = NotchGeometry.calculate()

        let notchH = geo?.notchHeight ?? 32
        let notchW = geo?.notchWidth ?? 185

        let contentHeight: CGFloat = 76
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

        let view = NotchNotificationView(
            notification: notification,
            hasNotch: hasNotch,
            notchWidth: notchW,
            notchHeight: notchH,
            onTap: { [weak self] in
                self?.dismiss()
                TerminalLauncher.focusClaudeCode(sessionId: notification.sessionId, sourceBundleId: notification.sourceBundleId)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = TransparentHostingView(rootView: AnyView(view))
        panel?.contentView = hostingView
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()

        // Set up hover monitor — only the visible content area below the notch is interactive.
        // The top notchH pixels overlap the physical notch and should always be click-through.
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

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        dismissTimer?.invalidate()
        dismissTimer = nil
        notifHoverMonitor.stop()

        guard let panel else {
            isDismissing = false
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1.0
            self?.isDismissing = false

            // Restore pill after notification dismisses
            if let self, self.hasPillSession, let pillPanel = self.pillPanel {
                pillPanel.alphaValue = 1.0
                pillPanel.orderFrontRegardless()
                self.pillHoverMonitor.start(panel: pillPanel)
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
