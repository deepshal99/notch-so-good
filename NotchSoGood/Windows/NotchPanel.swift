import AppKit
import SwiftUI

class NotchPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            orderOut(nil)
        }
    }
}

/// Polls mouse position at 30fps. Toggles `ignoresMouseEvents` so the panel
/// is click-through everywhere except the pill area. Drives hover state for SwiftUI.
class PillHoverMonitor: ObservableObject {
    @Published var isHovered = false

    private var timer: Timer?
    private weak var panel: NotchPanel?

    /// Collapsed pill rect in screen coordinates — used to detect hover-in.
    var collapsedScreenRect: NSRect = .zero
    /// Expanded pill rect in screen coordinates — used to detect hover-out (prevents flicker).
    var expandedScreenRect: NSRect = .zero

    func start(panel: NotchPanel) {
        self.panel = panel
        panel.ignoresMouseEvents = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel?.ignoresMouseEvents = true
    }

    private func update() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation

        // When not hovered, check collapsed rect (tight to the pill)
        // When hovered, check expanded rect (so dropdown doesn't flicker)
        let checkRect = isHovered
            ? expandedScreenRect.insetBy(dx: -6, dy: -6)
            : collapsedScreenRect.insetBy(dx: -4, dy: -4)
        let inside = checkRect.contains(mouse)

        // Toggle ignoresMouseEvents: only interactive when mouse is over pill area
        panel.ignoresMouseEvents = !inside

        if inside != isHovered {
            self.isHovered = inside
        }
    }

    deinit { stop() }
}
