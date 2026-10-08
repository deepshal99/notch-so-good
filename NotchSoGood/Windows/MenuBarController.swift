import AppKit
import SwiftUI
import Combine

/// The menu bar item and its panel. A plain NSStatusItem with our own
/// transparent panel, rather than MenuBarExtra: the system's menu window
/// paints its own glass (and rebuilds it on every update) with tighter
/// corners, so the island's shape could never be the window's shape.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private var hosting: NSHostingView<AnyView>?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var attentionObserver: AnyCancellable?
    private var contentSize: CGSize?

    /// Gap between the menu bar and the panel, as for system menus.
    private let gap: CGFloat = 6

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        statusItem = item
        updateIcon(needsAttention: NotificationManager.shared.needsAttention)
        attentionObserver = NotificationManager.shared.$activeSessions
            .map { sessions in sessions.contains { $0.status == .needsInput || $0.status == .needsPermission } }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] attention in self?.updateIcon(needsAttention: attention) }
    }

    private func updateIcon(needsAttention: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = needsAttention ? MenuBarGlyph.attention : MenuBarGlyph.normal
        button.setAccessibilityLabel(needsAttention ? "Notch So Good, a session needs you" : "Notch So Good")
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    /// When the panel last closed, so a click on the menu bar item that closed
    /// it (by taking focus) doesn't immediately open it again.
    private var lastClosed = Date.distantPast

    @objc func toggle() {
        if isOpen { close(); return }
        guard Date().timeIntervalSince(lastClosed) > 0.25 else { return }
        open()
    }

    func open() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Fresh content each time it opens: current sessions, limits refreshed.
        let content = MenuBarContentView(
            notificationManager: NotificationManager.shared,
            onClose: { [weak self] in self?.close() },
            onSize: { [weak self] size in self?.contentSize = size; self?.layout() }
        )
        let hosting = NSHostingView(rootView: AnyView(content))
        panel.contentView = hosting
        self.hosting = hosting
        layout(anchor: buttonWindow.frame)

        statusItem?.button?.highlight(true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        installDismissTriggers()
    }

    /// Everything that closes a menu: a click anywhere else (in another app or
    /// in our own notch windows), another app coming forward, a Space switch,
    /// the panel losing focus, Escape. Any one is enough; none depends on the
    /// panel having become key.
    private func installDismissTriggers() {
        removeDismissTriggers()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Clicks inside the panel, or on the menu bar item (which toggles), stay.
            if let self, event.window !== self.panel, event.window !== self.statusItem?.button?.window {
                self.close()
            }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
                Task { @MainActor in self?.close() }
            })
        }
    }

    private func removeDismissTriggers() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil
        localClickMonitor = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        hosting = nil
        contentSize = nil
        lastClosed = Date()
        statusItem?.button?.highlight(false)
        removeDismissTriggers()
    }

    /// Size to the content and hang under the menu bar item, kept on screen.
    func layout(anchor: NSRect? = nil) {
        guard let panel, let hosting else { return }
        let size = contentSize ?? hosting.fittingSize
        let anchor = anchor ?? statusItem?.button?.window?.frame ?? .zero
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = anchor.midX - size.width/2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = anchor.minY - gap
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> MenuPanel {
        let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        return panel
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in self.close() }
    }
}

/// A borderless panel that can take keys, for ⌘Q, ⌘, and Escape.
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        Task { @MainActor in MenuBarController.shared.close() }
    }
}
