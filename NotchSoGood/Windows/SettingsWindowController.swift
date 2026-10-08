import AppKit
import SwiftUI
import Sparkle

/// The Settings window: one dark, chromeless panel in the island's language,
/// closed with Done or Escape. A plain titled window keeps the system's rounded
/// corners and shadow; the title bar is hidden so the content owns the top.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// Set once at launch by the app delegate.
    var updater: SPUUpdater?
    private var window: NSWindow?

    func show() {
        if window == nil { build() }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// Tear the window down rather than hide it: hidden, its live character
    /// previews and observers would keep running for nothing.
    func close() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    private func build() {
        let view = SettingsView(notificationManager: NotificationManager.shared, updater: updater) { [weak self] in
            self?.close()
        }
        let size = NSSize(width: SettingsView.width, height: SettingsView.height)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        // The hosting view tracks the window exactly; letting a hosting
        // controller size the window left the content 14 pt narrower than it.
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).ignoresSafeArea())
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Panel.background)
        window.isReleasedWhenClosed = false
        window.title = "Notch So Good Settings"
        window.delegate = self
        self.window = window
    }
}
