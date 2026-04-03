import Foundation

/// Unix domain socket server that receives ALL events from Claude Code hooks.
/// Replaces the previous TCP server with a more secure, faster Unix socket.
///
/// Event types handled:
/// - PreToolUse: Auto-approve safe tools, show UI for dangerous ones (bidirectional)
/// - PostToolUse: Update session status back to running
/// - SessionStart: Start session tracking
/// - SessionEnd: Clean session end
/// - Stop: Session completed
/// - Notification: Show notification in notch
/// - UserPromptSubmit: User sent a message (session active)
/// - PreCompact: Context compaction starting
/// - SubagentStop: Subagent finished
class PermissionServer {
    static let shared = PermissionServer()
    static let socketPath = "/tmp/notchsogood.sock"

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.notchsogood.socket", qos: .userInitiated)

    struct PendingRequest {
        let id: String
        let toolName: String
        let toolInput: String
        let sessionId: String?
        let clientSocket: Int32
        let receivedAt: Date
    }

    /// Pending permission requests indexed by request ID — supports concurrent requests
    private var pendingRequests: [String: PendingRequest] = [:]
    private let lock = NSLock()

    /// All settings files Claude Code reads (global + global local).
    private static let settingsPaths: [String] = [
        NSHomeDirectory() + "/.claude/settings.json",
        NSHomeDirectory() + "/.claude/settings.local.json",
    ]

    // MARK: - Settings cache (avoid re-reading disk on every tool call)

    private static var cachedDangerousMode: Bool = false
    private static var cachedAllowRules: [String] = []
    private static var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 5

    private static func refreshCacheIfNeeded() {
        guard Date().timeIntervalSince(cacheTimestamp) > cacheTTL else { return }
        var dangerous = false
        var rules: [String] = []
        for path in settingsPaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if json["skipDangerousModePermissionPrompt"] as? Bool == true { dangerous = true }
            if json["dangerouslySkipPermissions"] as? Bool == true { dangerous = true }
            if let perms = json["permissions"] as? [String: Any],
               let allow = perms["allow"] as? [String] {
                rules.append(contentsOf: allow)
            }
        }
        cachedDangerousMode = dangerous
        cachedAllowRules = rules
        cacheTimestamp = Date()
    }

    static var isDangerousModeEnabled: Bool {
        refreshCacheIfNeeded()
        return cachedDangerousMode
    }

    static var allowRules: [String] {
        refreshCacheIfNeeded()
        return cachedAllowRules
    }

    // Built-in Claude Code tools that never need user approval
    static let safeTools: Set<String> = [
        "Read", "Glob", "Grep", "LSP", "Agent", "ToolSearch",
        "EnterPlanMode", "ExitPlanMode", "EnterWorktree", "ExitWorktree",
        "TaskGet", "TaskList", "TaskOutput", "TaskCreate", "TaskUpdate", "TaskStop",
        "CronList", "ListMcpResourcesTool", "ReadMcpResourceTool",
        "Skill", "SendMessage", "WebFetch", "WebSearch", "NotebookEdit",
        "mcp__conductor__AskUserQuestion",
        "mcp__conductor__DiffComment",
        "mcp__conductor__GetTerminalOutput",
        "mcp__conductor__GetWorkspaceDiff",
    ]

    private static let readOnlyKeywords = [
        "get_", "list_", "search_", "read_", "find_", "query_",
        "resolve", "snapshot", "watch", "fetch",
    ]

    static func isToolApproved(_ toolName: String, toolInput: String) -> Bool {
        if safeTools.contains(toolName) { return true }
        if isAllowedByRules(toolName: toolName, toolInput: toolInput) { return true }
        if toolName.hasPrefix("mcp__") {
            let parts = toolName.split(separator: "__", omittingEmptySubsequences: true)
            if let funcName = parts.last {
                let lower = funcName.lowercased()
                if readOnlyKeywords.contains(where: { lower.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private static func isAllowedByRules(toolName: String, toolInput: String) -> Bool {
        let rules = allowRules
        for rule in rules {
            if let parenIdx = rule.firstIndex(of: "(") {
                let ruleTool = String(rule[rule.startIndex..<parenIdx])
                guard toolName == ruleTool else { continue }
                let patternStart = rule.index(after: parenIdx)
                guard let parenEnd = rule.lastIndex(of: ")") else { continue }
                let pattern = String(rule[patternStart..<parenEnd])
                if pattern == "*" { return true }
                if pattern.hasSuffix(":*") {
                    let prefix = String(pattern.dropLast(2))
                    if toolInput.hasPrefix(prefix) { return true }
                }
            } else {
                if toolName == rule { return true }
                if toolName.hasPrefix(rule + "__") { return true }
            }
        }
        return false
    }

    // MARK: - Server lifecycle

    func start() {
        queue.async { [weak self] in
            self?.startServer()
        }
    }

    private func startServer() {
        guard serverSocket < 0 else { return }

        // Remove stale socket file
        unlink(Self.socketPath)
        // Also clean up legacy TCP port file
        unlink("/tmp/notchsogood.port")

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("PermissionServer: failed to create socket: \(errno)")
            return
        }

        // Non-blocking mode
        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let buf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
                strcpy(buf, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("PermissionServer: failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Allow all local users to connect (hooks run as same user anyway)
        chmod(Self.socketPath, 0o700)

        guard listen(serverSocket, 10) == 0 else {
            print("PermissionServer: failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        print("PermissionServer: listening on \(Self.socketPath)")

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        acceptSource?.resume()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)

        lock.lock()
        for (_, pending) in pendingRequests {
            close(pending.clientSocket)
        }
        pendingRequests.removeAll()
        lock.unlock()
    }

    // MARK: - Connection handling

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        // Prevent SIGPIPE on write to closed socket
        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        // Set non-blocking
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        // Read with timeout — hooks send small JSON payloads
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    break // EOF — sender closed write end
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty { break }
            } else {
                break
            }
        }

        guard !allData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: allData) as? [String: Any] else {
            close(clientSocket)
            return
        }

        let event = json["event"] as? String ?? ""
        let sessionId = json["session_id"] as? String
        let cwd = json["cwd"] as? String
        let sourceBundleId = json["source_app"] as? String

        switch event {
        case "PreToolUse":
            handlePreToolUse(json: json, clientSocket: clientSocket)

        case "PostToolUse":
            close(clientSocket)
            let toolName = json["tool_name"] as? String ?? ""
            DispatchQueue.main.async {
                NotificationManager.shared.handlePostToolUse(sessionId: sessionId, toolName: toolName)
            }

        case "SubagentStart":
            close(clientSocket)
            let subagentId = json["subagent_id"] as? String
            let description = json["description"] as? String
            DispatchQueue.main.async {
                NotificationManager.shared.handleSubagentStart(sessionId: sessionId, subagentId: subagentId, description: description)
            }

        case "SessionStart":
            close(clientSocket)
            let model = json["model"] as? String
            let sourceApp = json["source_app"] as? String
            DispatchQueue.main.async {
                NotificationManager.shared.startSession(sessionId: sessionId, displayName: cwd, sourceBundleId: sourceBundleId, sourceApp: sourceApp, model: model)
            }

        case "SessionEnd":
            close(clientSocket)
            DispatchQueue.main.async {
                NotificationManager.shared.endSession(sessionId: sessionId)
            }

        case "Stop":
            close(clientSocket)
            let message = json["last_assistant_message"] as? String ?? "Task completed"
            DispatchQueue.main.async {
                let notification = NotchNotification(
                    type: .complete,
                    message: String(message.prefix(200)),
                    sessionId: sessionId
                )
                NotificationManager.shared.handleNotification(notification)
            }

        case "Notification":
            close(clientSocket)
            let notifType = json["notification_type"] as? String ?? "general"
            let message = json["message"] as? String ?? "Claude needs attention"
            let title = json["title"] as? String
            let type: NotificationType = {
                switch notifType {
                case "permission_prompt": return .permission
                case "idle_prompt": return .question
                default: return .general
                }
            }()
            DispatchQueue.main.async {
                let notification = NotchNotification(
                    type: type,
                    message: String(message.prefix(200)),
                    title: title,
                    sessionId: sessionId
                )
                NotificationManager.shared.handleNotification(notification)
            }

        case "UserPromptSubmit":
            close(clientSocket)
            DispatchQueue.main.async {
                NotificationManager.shared.handleUserPromptSubmit(sessionId: sessionId)
            }

        case "PreCompact":
            close(clientSocket)
            DispatchQueue.main.async {
                NotificationManager.shared.updateSessionStatus(sessionId: sessionId, status: .compacting)
            }

        case "SubagentStop":
            close(clientSocket)
            let subagentId = json["subagent_id"] as? String
            DispatchQueue.main.async {
                NotificationManager.shared.handleSubagentStop(sessionId: sessionId, subagentId: subagentId)
            }

        default:
            close(clientSocket)
        }
    }

    // MARK: - PreToolUse (bidirectional — keeps socket open for response)

    private func handlePreToolUse(json: [String: Any], clientSocket: Int32) {
        let toolName = json["tool_name"] as? String ?? "Unknown"
        let toolInput = json["tool_input"] as? String ?? ""
        let sessionId = json["session_id"] as? String
        #if DEBUG
        let forceTest = json["force_test"] as? Bool ?? false
        #else
        let forceTest = false
        #endif

        // Track active tool for phase labels (even for auto-approved tools)
        let detail = toolInput.isEmpty ? nil : String(toolInput.prefix(60))
        DispatchQueue.main.async {
            NotificationManager.shared.handlePreToolUse(sessionId: sessionId, toolName: toolName, toolDetail: detail)
        }

        if !forceTest {
            if Self.isDangerousModeEnabled {
                sendSocketResponse(clientSocket: clientSocket, body: "{\"decision\":\"approve\"}")
                return
            }
            if Self.isToolApproved(toolName, toolInput: toolInput) {
                sendSocketResponse(clientSocket: clientSocket, body: "{\"decision\":\"approve\"}")
                return
            }
        }

        // Dangerous tool — need user approval
        let requestId = UUID().uuidString
        let request = PendingRequest(
            id: requestId,
            toolName: toolName,
            toolInput: toolInput,
            sessionId: sessionId,
            clientSocket: clientSocket,
            receivedAt: Date()
        )

        lock.lock()
        pendingRequests[requestId] = request
        lock.unlock()

        DispatchQueue.main.async {
            NotificationManager.shared.showPermissionRequest(
                requestId: requestId,
                toolName: toolName,
                toolInput: toolInput,
                sessionId: sessionId
            )
        }

        // Timeout after 2 minutes — close socket so hook outputs nothing
        queue.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.timeoutRequest(requestId: requestId)
        }
    }

    // MARK: - Permission response

    enum PermissionResponse {
        case allow
        case allowAlways
        case deny
    }

    func respond(requestId: String, response: PermissionResponse) {
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        switch response {
        case .allowAlways:
            let rule = Self.buildAllowRule(toolName: request.toolName, toolInput: request.toolInput)
            Self.addToAllowList(rule: rule)
            fallthrough
        case .allow:
            queue.async {
                self.sendSocketResponse(clientSocket: request.clientSocket, body: "{\"decision\":\"approve\"}")
            }
        case .deny:
            queue.async {
                self.sendSocketResponse(clientSocket: request.clientSocket, body: "{\"decision\":\"deny\",\"reason\":\"Denied from Notch So Good\"}")
            }
        }

        // After responding, check if there's another queued permission to show
        DispatchQueue.main.async {
            NotificationManager.shared.windowController.showNextQueuedPermission()
        }
    }

    // Back-compat wrapper
    func respond(requestId: String, approve: Bool) {
        respond(requestId: requestId, response: approve ? .allow : .deny)
    }

    /// Get count of pending permission requests (for queue management)
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests.count
    }

    /// Get all pending request IDs for a session
    func pendingRequestIds(for sessionId: String?) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests.values
            .filter { $0.sessionId == sessionId || sessionId == nil }
            .sorted { $0.receivedAt < $1.receivedAt }
            .map { $0.id }
    }

    // MARK: - Allow list management

    private static func buildAllowRule(toolName: String, toolInput: String) -> String {
        switch toolName {
        case "Bash":
            let cmd = toolInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = cmd.split(separator: " ", maxSplits: 2).map(String.init)
            if let first = words.first {
                let prefix = words.count >= 2 ? "\(first) \(words[1])" : first
                return "Bash(\(prefix):*)"
            }
            return "Bash"
        case "Edit", "Write", "NotebookEdit":
            return toolName
        default:
            return toolName
        }
    }

    @discardableResult
    private static func addToAllowList(rule: String) -> Bool {
        let path = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        var permissions = json["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []
        guard !allow.contains(rule) else { return true }
        allow.append(rule)
        permissions["allow"] = allow
        json["permissions"] = permissions

        guard let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: updated, encoding: .utf8) else { return false }

        do {
            try str.write(toFile: path, atomically: true, encoding: .utf8)
            cacheTimestamp = .distantPast
            return true
        } catch {
            return false
        }
    }

    // MARK: - Timeout & socket I/O

    private func timeoutRequest(requestId: String) {
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Close socket without response — hook outputs nothing, Claude Code uses normal flow
        close(request.clientSocket)

        DispatchQueue.main.async {
            NotificationManager.shared.windowController.dismissPermission(requestId: requestId)
        }
    }

    private func sendSocketResponse(clientSocket: Int32, body: String) {
        guard let data = body.data(using: .utf8) else {
            close(clientSocket)
            return
        }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            _ = write(clientSocket, base, data.count)
        }
        close(clientSocket)
    }
}
