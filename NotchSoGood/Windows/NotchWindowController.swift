import AppKit
import SwiftUI

class NotchWindowController {
    private var panel: NotchPanel?
    private var pillPanel: NotchPanel?
    private var dismissTimer: Timer?
    private var pillSessionId: String?
    private var pillStartTime: Date?
    private var isDismissing = false

    // MARK: - Session Pill (persistent minimized widget)

    func showSessionPill(sessionId: String?, startTime: Date) {
        pillSessionId = sessionId
        pillStartTime = startTime

        let hasNotch = NotchGeometry.hasNotch
        let geo = NotchGeometry.calculate()

        let notchW = geo?.notchWidth ?? 185
        let notchH = geo?.notchHeight ?? 32

        // Wing extension on each side of the notch
        let wingExtension: CGFloat = 44
        // Panel: notch width + both wings, extends a few pt below the notch so macOS renders it
        let pillPanelWidth: CGFloat = notchW + (wingExtension * 2)
        let pillPeekBelow: CGFloat = 6
        let pillPanelHeight: CGFloat = notchH + pillPeekBelow

        let frame = calculateFrame(
            panelWidth: pillPanelWidth,
            panelHeight: pillPanelHeight,
            hasNotch: hasNotch,
            geo: geo
        )

        if pillPanel == nil {
            pillPanel = NotchPanel(contentRect: frame)
            pillPanel?.level = .statusBar + 1
        } else {
            pillPanel?.setFrame(frame, display: true)
        }

        let pillView = VStack(spacing: 0) {
            SessionPillView(
                sessionId: sessionId,
                startTime: startTime,
                notchWidth: notchW,
                notchHeight: notchH,
                onTap: {
                    TerminalLauncher.focusClaudeCode(sessionId: sessionId, sourceBundleId: nil)
                }
            )
            .frame(width: pillPanelWidth, height: notchH)
            Spacer(minLength: 0)
        }
        .frame(width: pillPanelWidth, height: pillPanelHeight)

        let hostingView = NSHostingView(rootView: AnyView(pillView))
        hostingView.layer?.backgroundColor = .clear
        pillPanel?.contentView = hostingView
        pillPanel?.alphaValue = 1.0
        pillPanel?.orderFrontRegardless()
    }

    func hideSessionPill() {
        pillSessionId = nil
        pillStartTime = nil

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

        // Temporarily hide pill while notification is showing
        if isShowingPill {
            pillPanel?.orderOut(nil)
        }

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

        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.layer?.backgroundColor = .clear
        panel?.contentView = hostingView
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()

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

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1.0
            self?.isDismissing = false

            // Restore pill if session is still active
            if let sid = self?.pillSessionId, let startTime = self?.pillStartTime {
                self?.showSessionPill(sessionId: sid, startTime: startTime)
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
            // No notch — position just below the menu bar, centered on screen
            let fallback = NotchGeometry.fallbackOrigin()
            let x = fallback.x - panelWidth / 2
            // fallback.y is already screenTop - menubarHeight
            let y = fallback.y - panelHeight
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        }
    }
}
