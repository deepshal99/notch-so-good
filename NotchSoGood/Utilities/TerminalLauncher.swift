import AppKit

struct TerminalLauncher {
    /// Focus the app that originated the Claude Code session, then raise the
    /// window whose title best matches the session's working directory.
    static func focusClaudeCode(sessionId: String? = nil, sourceBundleId: String? = nil, cwd: String? = nil) {
        // 1. Try the specific source app passed from the hook / stored per-session
        if let bundleId = sourceBundleId, !bundleId.isEmpty {
            if activateApp(bundleId: bundleId, cwd: cwd) { return }
        }

        // 2. Walk known terminals/IDEs — activate the first running one
        let knownApps = [
            "com.google.antigravity",        // Antigravity IDE
            "com.conductor.app",             // Conductor
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
            if activateApp(bundleId: bundleId, cwd: cwd) { return }
        }

        // 3. Last resort: open Terminal.app
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - App activation with window matching

    @discardableResult
    private static func activateApp(bundleId: String, cwd: String? = nil) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return false
        }

        if let cwd = cwd, !cwd.isEmpty {
            // Try terminal-specific deep-linking first (tab/pane level precision)
            if !deepLinkToTab(bundleId: bundleId, cwd: cwd) {
                // Fall back to AX window-title matching
                raiseMatchingWindow(app: app, cwd: cwd)
            }
        }

        app.activate()
        return true
    }

    // MARK: - Terminal-specific deep-linking

    /// Attempts to focus the exact tab/pane matching the cwd using terminal-specific APIs.
    /// Returns true if the terminal supports deep-linking and the command was dispatched.
    private static func deepLinkToTab(bundleId: String, cwd: String) -> Bool {
        switch bundleId {
        case "com.googlecode.iterm2":
            return focusITerm2Tab(cwd: cwd)
        case "com.apple.Terminal":
            return focusTerminalTab(cwd: cwd)
        case "net.kovidgoyal.kitty":
            return focusKittyWindow(cwd: cwd)
        case "com.github.wez.wezterm":
            return focusWezTermTab(cwd: cwd)
        default:
            return false
        }
    }

    // MARK: - iTerm2: AppleScript tab focus by cwd

    private static func focusITerm2Tab(cwd: String) -> Bool {
        // iTerm2 exposes session properties via AppleScript including the
        // variable "path" which reflects the current working directory.
        // We enumerate all sessions and select the one whose path matches.
        let escaped = cwd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                tell w
                    repeat with t in tabs
                        tell t
                            repeat with s in sessions
                                tell s
                                    set p to variable named "path"
                                    if p ends with "\(escaped)" or p is equal to "\(escaped)" then
                                        select
                                        tell t to select
                                        return true
                                    end if
                                end tell
                            end repeat
                        end tell
                    end repeat
                end tell
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Terminal.app: AppleScript tab focus by cwd

    private static func focusTerminalTab(cwd: String) -> Bool {
        // Terminal.app tabs have a "current settings" and a custom title,
        // but the most reliable match is the tty's working directory.
        // We use `lsof` to find which tty is in our cwd, then select that tab.
        // Simpler approach: match window/tab name which Terminal.app sets to the cwd.
        let escaped = cwd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let projectName = (cwd as NSString).lastPathComponent
        let escapedProject = projectName.replacingOccurrences(of: "\\", with: "\\\\")
                                        .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            repeat with w in windows
                tell w
                    repeat with t from 1 to count of tabs
                        set tabName to name of tab t
                        if tabName contains "\(escaped)" or tabName contains "\(escapedProject)" then
                            set selected tab to tab t
                            set index to 1
                            return true
                        end if
                    end repeat
                end tell
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Kitty: remote control window focus by cwd

    private static func focusKittyWindow(cwd: String) -> Bool {
        // Kitty supports remote control via `kitty @ focus-window --match`.
        // The `cwd` matcher finds the window/tab whose shell is in the given directory.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["kitty", "@", "focus-window", "--match", "cwd:\(cwd)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - WezTerm: CLI tab activation by cwd

    private static func focusWezTermTab(cwd: String) -> Bool {
        // WezTerm exposes a CLI: `wezterm cli list` returns JSON with pane info including cwd.
        // We find the pane ID matching our cwd, then activate it.
        let listTask = Process()
        listTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        listTask.arguments = ["wezterm", "cli", "list", "--format", "json"]
        let pipe = Pipe()
        listTask.standardOutput = pipe
        listTask.standardError = FileHandle.nullDevice
        do {
            try listTask.run()
            listTask.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }

        // Find the pane whose cwd matches
        let cwdLower = cwd.lowercased()
        let projectName = (cwd as NSString).lastPathComponent.lowercased()
        var bestPaneId: Int?
        var bestScore = 0

        for pane in panes {
            guard let paneCwd = pane["cwd"] as? String,
                  let paneId = pane["pane_id"] as? Int else { continue }

            let paneCwdLower = paneCwd.lowercased()
            var score = 0
            if paneCwdLower == cwdLower || paneCwdLower.hasSuffix(cwdLower) {
                score = 100
            } else if !projectName.isEmpty && paneCwdLower.hasSuffix(projectName) {
                score = 50
            }

            if score > bestScore {
                bestScore = score
                bestPaneId = paneId
            }
        }

        guard let paneId = bestPaneId else { return false }

        let activateTask = Process()
        activateTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        activateTask.arguments = ["wezterm", "cli", "activate-pane", "--pane-id", "\(paneId)"]
        activateTask.standardOutput = FileHandle.nullDevice
        activateTask.standardError = FileHandle.nullDevice
        do {
            try activateTask.run()
            activateTask.waitUntilExit()
            return activateTask.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Window-level targeting via Accessibility API

    /// Uses the macOS Accessibility API to find and raise the window whose title
    /// best matches the session's working directory.
    private static func raiseMatchingWindow(app: NSRunningApplication, cwd: String) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return
        }

        let cwdLower = cwd.lowercased()
        let projectName = (cwd as NSString).lastPathComponent.lowercased()

        var bestWindow: AXUIElement?
        var bestScore = 0

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }

            let titleLower = title.lowercased()
            var score = 0

            if titleLower.contains(cwdLower) {
                score = 100
            } else if !projectName.isEmpty && titleLower.contains(projectName) {
                score = 50
            }

            if score > bestScore {
                bestScore = score
                bestWindow = window
            }
        }

        if let window = bestWindow {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    // MARK: - Helpers

    /// Runs an AppleScript and returns true if the script returned `true`.
    private static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return false }
        return result.booleanValue
    }
}
