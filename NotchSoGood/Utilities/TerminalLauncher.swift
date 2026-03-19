import AppKit

struct TerminalLauncher {
    /// Focus the app that originated the Claude Code session.
    /// If a specific bundle ID was passed from the hook, use that.
    /// Otherwise, walk through known terminal/IDE apps.
    static func focusClaudeCode(sessionId: String? = nil, sourceBundleId: String? = nil) {
        // 1. Try the specific source app passed from the hook
        if let bundleId = sourceBundleId, !bundleId.isEmpty {
            if activateApp(bundleId: bundleId) { return }
        }

        // 2. Walk known terminals/IDEs
        let knownApps = [
            "com.google.antigravity",        // Antigravity IDE
            "com.cursor.Cursor",             // Cursor
            "com.microsoft.VSCode",          // VS Code
            "com.todesktop.230313mzl4w4u92", // Cursor (alt ID)
            "com.mitchellh.ghostty",         // Ghostty
            "com.googlecode.iterm2",         // iTerm2
            "net.kovidgoyal.kitty",          // Kitty
            "dev.warp.Warp-Stable",          // Warp
            "io.alacritty",                  // Alacritty
            "com.github.wez.wezterm",        // WezTerm
            "co.zeit.hyper",                 // Hyper
            "com.raphaelamorim.rio",         // Rio
            "com.apple.Terminal",            // Terminal.app (last resort)
        ]

        for bundleId in knownApps {
            if activateApp(bundleId: bundleId) { return }
        }

        // 3. Last resort: open Terminal.app
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @discardableResult
    private static func activateApp(bundleId: String) -> Bool {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
            return true
        }
        return false
    }
}
