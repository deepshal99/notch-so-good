import AppKit
import SwiftUI

class NotchWindowController {
    private var panel: NotchPanel?
    private var pillPanel: NotchPanel?
    private var dismissTimer: Timer?
    private var isDismissing = false
    private var hasPillSession = false

    // Pill sizing constants (must match SessionPillView max)
    private let wingExpanded: CGFloat = 110
    private let maxDropHeight: CGFloat = 160  // 4 rows * 36 + padding
    private let pillPeekBelow: CGFloat = 6

    // MARK: - Session Pill (persistent minimized widget)

    func showSessionPill(sessions: [(id: String, startTime: Date)], primaryStartTime: Date) {
        hasPillSession = true

        let hasNotch = NotchGeometry.hasNotch
        let geo = NotchGeometry.calculate()

        let notchW = geo?.notchWidth ?? 185
        let notchH = geo?.notchHeight ?? 32

        // Always use max expanded size — SwiftUI handles visual sizing
        let maxWidth = notchW + (wingExpanded * 2)
        let maxHeight = notchH + maxDropHeight + pillPeekBelow

        let frame = calculateFrame(
            panelWidth: maxWidth,
            panelHeight: maxHeight,
            hasNotch: hasNotch,
            geo: geo
        )

        if pillPanel == nil {
            pillPanel = NotchPanel(contentRect: frame)
            pillPanel?.level = .statusBar + 1
        } else {
            pillPanel?.setFrame(frame, display: true)
        }

        let pillView = SessionPillView(
            sessions: sessions,
            primaryStartTime: primaryStartTime,
            notchWidth: notchW,
            notchHeight: notchH,
            onTap: { sessionId in
                TerminalLauncher.focusClaudeCode(sessionId: sessionId, sourceBundleId: nil)
            }
        )

        let container = VStack(spacing: 0) {
            pillView
            Spacer(minLength: 0)
        }
        .frame(width: maxWidth, height: maxHeight)

        let hostingView = NSHostingView(rootView: AnyView(container))
        hostingView.layer?.backgroundColor = .clear
        pillPanel?.contentView = hostingView
        pillPanel?.alphaValue = 1.0
        pillPanel?.orderFrontRegardless()
    }

    func hideSessionPill() {
        hasPillSession = false

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
            panel?.level = .statusBar + 2  // Above the pill panel
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
