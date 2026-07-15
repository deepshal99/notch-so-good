import AppKit
import SwiftUI

/// NSHostingView subclass that is fully transparent — no default background.
class TransparentHostingView: NSHostingView<AnyView> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Remove the default opaque background NSHostingView draws
        guard let layer = self.layer else { return }
        layer.backgroundColor = .clear
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Don't draw any background
        NSColor.clear.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

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
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        // Needed so local mouseMoved monitors fire while the panel is interactive
        acceptsMouseMovedEvents = true
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

/// Event-driven hover tracking — fires only when the mouse actually moves
/// (no fixed-rate polling). Toggles `ignoresMouseEvents` so the panel
/// is click-through everywhere except the pill area. Drives hover state for SwiftUI.
class PillHoverMonitor: ObservableObject {
    @Published var isHovered = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var panel: NotchPanel?

    /// Collapsed pill rect in screen coordinates — used to detect hover-in.
    var collapsedScreenRect: NSRect = .zero
    /// Expanded pill rect in screen coordinates — used to detect hover-out (prevents flicker).
    var expandedScreenRect: NSRect = .zero

    func start(panel: NotchPanel) {
        stop()
        self.panel = panel
        panel.ignoresMouseEvents = true

        // Global monitor: mouse moves over other apps (panel is click-through).
        // Local monitor: mouse moves over our own interactive panel.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.update()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.update()
            return event
        }
        update()
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
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

/// Lightweight event-driven hover monitor for the notification panel.
/// Makes the panel click-through except when the mouse is over the visible content.
class NotificationHoverMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var panel: NotchPanel?

    /// The visible notification rect in screen coordinates.
    var contentScreenRect: NSRect = .zero

    func start(panel: NotchPanel) {
        stop()
        self.panel = panel
        panel.ignoresMouseEvents = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.update()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.update()
            return event
        }
        update()
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        panel?.ignoresMouseEvents = true
    }

    private func update() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let inside = contentScreenRect.insetBy(dx: -4, dy: -4).contains(mouse)
        panel.ignoresMouseEvents = !inside
    }

    deinit { stop() }
}
