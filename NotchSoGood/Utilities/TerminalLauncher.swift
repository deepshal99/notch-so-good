import AppKit

struct TerminalLauncher {
    /// Focus the app that owns an agent session, then raise the window whose
    /// title best matches the session's working directory.
    ///
    /// Resolution is ordered most-precise-first:
    ///  1. the hook process's ancestry — the terminal or IDE that literally
    ///     spawned the agent, resolved live via sysctl;
    ///  2. the bundle id the hook reported (`__CFBundleIdentifier`), which is
    ///     empty under tmux / ssh / most login shells;
    ///  3. a walk of known terminals and IDEs, as a last guess.
    ///
    /// If none of those is running we do nothing. Launching an unrelated
    /// Terminal window — the old fallback — looks exactly like "it took me
    /// somewhere that isn't my session".
    @discardableResult
    static func focusClaudeCode(
        sessionId: String? = nil,
        sourceBundleId: String? = nil,
        cwd: String? = nil,
        sourcePid: pid_t? = nil
    ) -> Bool {
        guard let app = resolveApp(sourcePid: sourcePid, sourceBundleId: sourceBundleId) else {
            return false
        }

        // Activate immediately so the click feels instant, then do the slower
        // tab/window targeting off the main thread.
        let activated = app.activate()
        if !activated {
            // A single retry covers the common "app was mid-launch" race.
            app.activate(options: [.activateAllWindows])
        }

        if let cwd = NotchNotification.nonEmpty(cwd) {
            let bundleId = app.bundleIdentifier ?? ""
            targetingQueue.async {
                if !deepLinkToTab(bundleId: bundleId, cwd: cwd) {
                    raiseMatchingWindow(app: app, cwd: cwd)
                }
            }
        }
        return true
    }

    /// AppleScript and CLI round-trips can take hundreds of milliseconds; never
    /// run them on the main thread where they'd freeze the notch.
    private static let targetingQueue = DispatchQueue(label: "com.notchsogood.focus", qos: .userInitiated)

    // MARK: - Which app owns this session

    private static func resolveApp(sourcePid: pid_t?, sourceBundleId: String?) -> NSRunningApplication? {
        // 1. Live process ancestry — the strongest signal available.
        if let sourcePid, let owner = ProcessTree.owningApp(of: sourcePid), !owner.isTerminated {
            return owner
        }

        // 2. The bundle id the hook captured from the environment.
        if let bundleId = NotchNotification.nonEmpty(sourceBundleId),
           let app = runningApp(bundleId: bundleId) {
            return app
        }

        // 3. Known terminals and IDEs, most-specific first.
        for bundleId in knownApps {
            if let app = runningApp(bundleId: bundleId) { return app }
        }

        return nil
    }

    private static func runningApp(bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first { !$0.isTerminated }
    }

    private static let knownApps = [
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

    // MARK: - Terminal-specific deep-linking

    /// Focus the exact tab/pane matching the cwd using terminal-specific APIs.
    /// Returns true only when the terminal confirmed a match.
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
        // iTerm2 exposes each session's working directory as the "path" variable.
        let escaped = appleScriptString(cwd)
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                tell w
                    repeat with t in tabs
                        tell t
                            repeat with s in sessions
                                tell s
                                    set p to variable named "path"
                                    if p is equal to \(escaped) then
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
        // Terminal.app puts the directory (or its leaf) in the tab's name.
        let escapedPath = appleScriptString(cwd)
        let escapedProject = appleScriptString((cwd as NSString).lastPathComponent)
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t from 1 to count of tabs of w
                    set tabName to name of tab t of w
                    if tabName contains \(escapedPath) or tabName contains \(escapedProject) then
                        set selected tab of w to tab t of w
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Kitty: remote control window focus by cwd

    private static func focusKittyWindow(cwd: String) -> Bool {
        // `kitty @ focus-window --match cwd:…` needs the real binary path: a
        // GUI-launched app inherits a bare PATH, so `/usr/bin/env kitty` — what
        // this used to do — never resolved and the deep link silently never ran.
        guard let kitty = executablePath(
            "kitty",
            extraCandidates: ["/Applications/kitty.app/Contents/MacOS/kitty"]
        ) else { return false }
        return run(kitty, ["@", "focus-window", "--match", "cwd:\(cwd)"]).status == 0
    }

    // MARK: - WezTerm: CLI pane activation by cwd

    private static func focusWezTermTab(cwd: String) -> Bool {
        guard let wezterm = executablePath(
            "wezterm",
            extraCandidates: ["/Applications/WezTerm.app/Contents/MacOS/wezterm"]
        ) else { return false }

        let listed = run(wezterm, ["cli", "list", "--format", "json"])
        guard listed.status == 0,
              let panes = try? JSONSerialization.jsonObject(with: listed.output) as? [[String: Any]] else {
            return false
        }

        var bestPaneId: Int?
        var bestScore = 0
        for pane in panes {
            guard let paneCwd = pane["cwd"] as? String,
                  let paneId = pane["pane_id"] as? Int else { continue }
            // WezTerm reports cwd as a file:// URL on some versions.
            let normalized = URL(string: paneCwd)?.path ?? paneCwd
            let score = WindowMatcher.score(candidate: normalized, cwd: cwd)
            if score > bestScore {
                bestScore = score
                bestPaneId = paneId
            }
        }

        guard let paneId = bestPaneId else { return false }
        return run(wezterm, ["cli", "activate-pane", "--pane-id", "\(paneId)"]).status == 0
    }

    // MARK: - Window-level targeting via Accessibility API

    /// Find and raise the window whose title best matches the session's cwd.
    /// Silently does nothing without Accessibility access — the menu bar shows a
    /// prompt for that.
    private static func raiseMatchingWindow(app: NSRunningApplication, cwd: String) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return
        }

        var bestWindow: AXUIElement?
        var bestScore = 0

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }
            let score = WindowMatcher.score(candidate: title, cwd: cwd)
            if score > bestScore {
                bestScore = score
                bestWindow = window
            }
        }

        guard let window = bestWindow else { return }
        // Raise alone often leaves the window unfocused; make it main too.
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: - Matching

    // MARK: - Process helpers

    /// Locate a CLI tool without relying on PATH, which is near-empty for
    /// GUI-launched apps.
    private static func executablePath(_ name: String, extraCandidates: [String] = []) -> String? {
        let dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/bin",
        ]
        let candidates = dirs.map { $0 + "/" + name } + extraCandidates
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return (-1, Data())
        }
        // Read before waiting so a chatty tool can't fill the pipe and deadlock.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, output)
    }

    /// Quote and escape a value for embedding in AppleScript source.
    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Runs an AppleScript and returns true if the script returned `true`.
    /// Through `osascript`, because NSAppleScript isn't safe off the main
    /// thread and these run on the targeting queue.
    private static func runAppleScript(_ source: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return false }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}
