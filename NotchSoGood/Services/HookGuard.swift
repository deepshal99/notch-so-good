import Foundation

/// Keeps the hooks in place. Claude Code updates, other tools and hand edits
/// sometimes rewrite the agents' settings and drop ours, and then the notch
/// goes quiet with no clue why. This watches those files and puts the hooks
/// back, at most once every ten minutes so it can never fight another tool.
final class HookGuard {
    static let shared = HookGuard()

    private var sources: [DispatchSourceFileSystemObject] = []
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var lastRepair = Date.distantPast
    private let queue = DispatchQueue(label: "com.notchsogood.hookguard", qos: .utility)

    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]

    func start() {
        guard sources.isEmpty else { return }
        let home = NSHomeDirectory()
        let claude = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
        // The folders (a file replaced or created) and the files (edited in place).
        for dir in [claude, home + "/.codex"] {
            if let source = watch(dir, onEvent: { [weak self] in self?.soon(); self?.watchFiles(claude: claude, home: home) }) {
                sources.append(source)
            }
        }
        watchFiles(claude: claude, home: home)
        // And now and then, for anything the watch missed.
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.soon() }
    }

    private func watchFiles(claude: String, home: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for file in [claude + "/settings.json", home + "/.codex/hooks.json"] {
                // A replaced file is a new file: drop the old watch and start again.
                if let old = self.fileSources[file], old.isCancelled == false, FileManager.default.fileExists(atPath: file) { continue }
                self.fileSources[file]?.cancel()
                self.fileSources[file] = self.watch(file) { [weak self] in
                    self?.soon()
                    self?.fileSources[file]?.cancel()
                    self?.fileSources[file] = nil
                    self?.watchFiles(claude: claude, home: home)
                }
            }
        }
    }

    private func watch(_ path: String, onEvent: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: queue)
        source.setEventHandler(handler: onEvent)
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func soon() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work
        queue.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func check() {
        guard Health.hooksMissing(), Date().timeIntervalSince(lastRepair) > 10 * 60 else { return }
        lastRepair = Date()
        DispatchQueue.main.async {
            NotificationManager.shared.installHooks()
        }
    }
}
