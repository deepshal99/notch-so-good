import AppKit
import Darwin

/// Finds the GUI application that owns an arbitrary process.
///
/// Hook scripts run as descendants of whatever window the user was actually
/// looking at (terminal → shell → agent → hook), so the first ancestor AppKit
/// recognises as a running application *is* the thing to focus. This is far
/// more reliable than the `__CFBundleIdentifier` env var the hooks used to
/// send, which is empty under tmux, ssh, and most login-shell setups — the
/// case where clicking the pill used to focus a random terminal or nothing.
enum ProcessTree {
    /// Parent pid via sysctl, or nil if the process is gone.
    static func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 1 ? ppid : nil
    }

    /// Walk up from `pid` until we hit a process AppKit knows as an app.
    /// Skips ourselves so a hook that somehow runs under us can't self-match.
    static func owningApp(of pid: pid_t, maxDepth: Int = 16) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<maxDepth {
            if let app = NSRunningApplication(processIdentifier: current),
               let bundleId = app.bundleIdentifier,
               bundleId != Bundle.main.bundleIdentifier {
                return app
            }
            guard let parent = parentPid(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    /// Convenience: bundle identifier of the owning app.
    static func owningAppBundleId(of pid: pid_t) -> String? {
        owningApp(of: pid)?.bundleIdentifier
    }
}
