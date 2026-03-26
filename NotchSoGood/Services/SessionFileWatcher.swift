import Foundation

/// Watches Claude Code's JSONL conversation files for interrupt signals.
/// When a user presses Ctrl+C during a tool execution, the JSONL file gets a
/// tool_result entry with `is_error: true` and content containing "interrupted".
/// We detect this to immediately dismiss pending permission dialogs.
class SessionFileWatcher {
    static let shared = SessionFileWatcher()

    private let queue = DispatchQueue(label: "com.notchsogood.filewatcher", qos: .utility)
    private var watchers: [String: FileWatcherState] = [:]  // sessionId -> state
    private let lock = NSLock()

    private struct FileWatcherState {
        let sessionId: String
        let filePath: String
        var fileOffset: UInt64
        var source: DispatchSourceFileSystemObject?
        var fileDescriptor: Int32
    }

    private let projectsDir = NSHomeDirectory() + "/.claude/projects"

    // MARK: - Public API

    /// Start watching a session's JSONL file for interrupts
    func startWatching(sessionId: String, cwd: String?) {
        queue.async { [weak self] in
            self?.setupWatcher(sessionId: sessionId, cwd: cwd)
        }
    }

    /// Stop watching a session
    func stopWatching(sessionId: String) {
        queue.async { [weak self] in
            self?.teardownWatcher(sessionId: sessionId)
        }
    }

    /// Stop all watchers
    func stopAll() {
        lock.lock()
        let ids = Array(watchers.keys)
        lock.unlock()
        for id in ids {
            teardownWatcher(sessionId: id)
        }
    }

    // MARK: - Private

    private func setupWatcher(sessionId: String, cwd: String?) {
        // Already watching this session
        lock.lock()
        if watchers[sessionId] != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        // Find the JSONL file — try direct path construction first, then glob
        guard let filePath = findJsonlFile(sessionId: sessionId, cwd: cwd) else {
            // File might not exist yet — retry after a delay
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let alreadyWatching = self.watchers[sessionId] != nil
                self.lock.unlock()
                if !alreadyWatching {
                    if let path = self.findJsonlFile(sessionId: sessionId, cwd: cwd) {
                        self.beginWatching(sessionId: sessionId, filePath: path)
                    }
                }
            }
            return
        }

        beginWatching(sessionId: sessionId, filePath: filePath)
    }

    private func beginWatching(sessionId: String, filePath: String) {
        let fd = open(filePath, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return }

        // Start from end of file — we only care about new writes
        let fileSize = lseek(fd, 0, SEEK_END)
        let offset = fileSize >= 0 ? UInt64(fileSize) : 0

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        let state = FileWatcherState(
            sessionId: sessionId,
            filePath: filePath,
            fileOffset: offset,
            source: source,
            fileDescriptor: fd
        )

        source.setEventHandler { [weak self] in
            self?.handleFileChange(sessionId: sessionId)
        }

        source.setCancelHandler {
            close(fd)
        }

        lock.lock()
        watchers[sessionId] = state
        lock.unlock()

        source.resume()
    }

    private func teardownWatcher(sessionId: String) {
        lock.lock()
        guard var state = watchers.removeValue(forKey: sessionId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        state.source?.cancel()
        state.source = nil
    }

    private func handleFileChange(sessionId: String) {
        lock.lock()
        guard let state = watchers[sessionId] else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Read new bytes from the file
        guard let fileHandle = FileHandle(forReadingAtPath: state.filePath) else { return }
        defer { fileHandle.closeFile() }

        fileHandle.seek(toFileOffset: state.fileOffset)
        let newData = fileHandle.readDataToEndOfFile()
        guard !newData.isEmpty else { return }

        let newOffset = state.fileOffset + UInt64(newData.count)

        // Update offset
        lock.lock()
        watchers[sessionId]?.fileOffset = newOffset
        lock.unlock()

        // Parse new lines for interrupt signals
        guard let text = String(data: newData, encoding: .utf8) else { return }

        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Check for interrupt: tool_result with is_error and "interrupted" in content
            if json["type"] as? String == "user",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result",
                       block["is_error"] as? Bool == true {
                        let resultContent = block["content"] as? String ?? ""
                        if resultContent.localizedCaseInsensitiveContains("interrupted") {
                            handleInterrupt(sessionId: sessionId)
                            return
                        }
                    }
                }
            }
        }
    }

    private func handleInterrupt(sessionId: String) {
        DispatchQueue.main.async {
            // Cancel any pending permission requests for this session
            let pendingIds = PermissionServer.shared.pendingRequestIds(for: sessionId)
            for reqId in pendingIds {
                PermissionServer.shared.respond(requestId: reqId, response: .deny)
            }

            // Dismiss the permission notification if it's for this session
            NotificationManager.shared.windowController.dismiss()

            // Update session status
            NotificationManager.shared.updateSessionStatus(sessionId: sessionId, status: .needsInput)
        }
    }

    // MARK: - File discovery

    private func findJsonlFile(sessionId: String, cwd: String?) -> String? {
        // Strategy 1: If we know the cwd, construct the path directly
        if let cwd = cwd, !cwd.isEmpty {
            let encoded = cwd.replacingOccurrences(of: "/", with: "-")
            let directPath = "\(projectsDir)/\(encoded)/\(sessionId).jsonl"
            if FileManager.default.fileExists(atPath: directPath) {
                return directPath
            }
            // Also try with spaces replaced by hyphens
            let encodedHyphens = encoded.replacingOccurrences(of: " ", with: "-")
            let hyphenPath = "\(projectsDir)/\(encodedHyphens)/\(sessionId).jsonl"
            if FileManager.default.fileExists(atPath: hyphenPath) {
                return hyphenPath
            }
        }

        // Strategy 2: Glob for the session ID across all project dirs
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return nil }

        for dir in projectDirs {
            let candidate = "\(projectsDir)/\(dir)/\(sessionId).jsonl"
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}
