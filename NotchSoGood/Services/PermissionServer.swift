import Foundation
import Network

/// Local TCP server that receives permission requests from Claude Code's PreToolUse hook.
/// Safe tools (Read, Grep, etc.) are auto-approved instantly.
/// Dangerous tools (Bash, Edit, Write) block until the user clicks Approve/Deny in the notch.
class PermissionServer {
    static let shared = PermissionServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.notchsogood.permission-server")
    private let port: UInt16 = 27182

    struct PendingRequest {
        let id: String
        let toolName: String
        let toolInput: String
        let sessionId: String?
        let connection: NWConnection
    }

    private var pendingRequests: [String: PendingRequest] = [:]
    private let lock = NSLock()

    /// All settings files Claude Code reads (global + global local).
    /// Project-level settings are checked in the hook via git root.
    private static let settingsPaths: [String] = [
        NSHomeDirectory() + "/.claude/settings.json",
        NSHomeDirectory() + "/.claude/settings.local.json",
    ]

    // MARK: - Settings cache (avoid re-reading disk on every tool call)

    /// Cached settings state — refreshed at most once per `cacheTTL` seconds.
    private static var cachedDangerousMode: Bool = false
    private static var cachedAllowRules: [String] = []
    private static var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 5 // re-read settings at most every 5s

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

    /// Returns true if the user has enabled dangerous mode / bypass permissions in Claude Code.
    static var isDangerousModeEnabled: Bool {
        refreshCacheIfNeeded()
        return cachedDangerousMode
    }

    /// Collect all `permissions.allow` rules from Claude Code settings.
    static var allowRules: [String] {
        refreshCacheIfNeeded()
        return cachedAllowRules
    }

    // Built-in Claude Code tools that never need user approval (read-only / non-destructive)
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

    /// Keywords in MCP tool function names that indicate read-only operations.
    /// Used as a heuristic fallback so we don't need to hardcode every MCP server's tools.
    private static let readOnlyKeywords = [
        "get_", "list_", "search_", "read_", "find_", "query_",
        "resolve", "snapshot", "watch", "fetch",
    ]

    /// Check if a tool is safe (no approval needed) using multiple strategies:
    /// 1. Built-in safe tools list
    /// 2. User's permissions.allow rules (tool already allowed in Claude Code)
    /// 3. MCP read-only heuristic (function name contains get/list/search/etc.)
    static func isToolApproved(_ toolName: String, toolInput: String) -> Bool {
        // 1. Built-in safe tools
        if safeTools.contains(toolName) { return true }

        // 2. Check user's allow rules from Claude Code settings
        if isAllowedByRules(toolName: toolName, toolInput: toolInput) { return true }

        // 3. MCP read-only heuristic — extract the function part after the last "__"
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

    /// Match a tool against the user's `permissions.allow` patterns.
    /// Supports: "Edit", "Bash(git commit:*)", "mcp__pencil" (prefix), etc.
    private static func isAllowedByRules(toolName: String, toolInput: String) -> Bool {
        let rules = allowRules
        for rule in rules {
            if let parenIdx = rule.firstIndex(of: "(") {
                // Pattern rule: "Bash(git commit:*)"
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
                // Simple rule: "Edit" or prefix: "mcp__pencil"
                if toolName == rule { return true }
                // Prefix match for MCP namespaces: "mcp__pencil" matches "mcp__pencil__batch_design"
                if toolName.hasPrefix(rule + "__") { return true }
            }
        }
        return false
    }

    func start() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    try? String(self.port).write(
                        toFile: "/tmp/notchsogood.port",
                        atomically: true,
                        encoding: .utf8
                    )
                case .failed(let error):
                    print("PermissionServer failed: \(error)")
                    // Try to restart after a brief delay
                    self.listener = nil
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.start()
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("PermissionServer: Failed to start on port \(port): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: "/tmp/notchsogood.port")
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        // Read the full HTTP request in one chunk (requests are tiny, <2KB)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil,
                  let raw = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Extract body from HTTP POST
            guard let bodyRange = raw.range(of: "\r\n\r\n") else {
                // Might be a health check or incomplete request
                self.sendHTTPResponse(connection: connection, body: "{}")
                return
            }

            let body = String(raw[bodyRange.upperBound...])
            self.processRequest(body: body, connection: connection)
        }
    }

    private func processRequest(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendHTTPResponse(connection: connection, body: "{}")
            return
        }

        let toolName = json["tool_name"] as? String ?? "Unknown"
        let toolInput = json["tool_input"] as? String ?? ""
        let sessionId = json["session_id"] as? String
        #if DEBUG
        let forceTest = json["force_test"] as? Bool ?? false
        #else
        let forceTest = false
        #endif

        // Skip auto-approve checks when force_test is set (debug UI testing only)
        if !forceTest {
            // Auto-approve everything if user has dangerous mode enabled
            if Self.isDangerousModeEnabled {
                sendHTTPResponse(connection: connection, body: "{\"decision\":\"approve\"}")
                return
            }

            // Auto-approve safe tools and tools already allowed in Claude Code settings
            if Self.isToolApproved(toolName, toolInput: toolInput) {
                sendHTTPResponse(connection: connection, body: "{\"decision\":\"approve\"}")
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
            connection: connection
        )

        lock.lock()
        pendingRequests[requestId] = request
        lock.unlock()

        // Show approval UI on main thread
        DispatchQueue.main.async {
            NotificationManager.shared.showPermissionRequest(
                requestId: requestId,
                toolName: toolName,
                toolInput: toolInput,
                sessionId: sessionId
            )
        }

        // Timeout after 2 minutes — send empty response so hook outputs nothing
        // (Claude Code falls back to its normal terminal permission flow)
        queue.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.timeoutRequest(requestId: requestId)
        }
    }

    enum PermissionResponse {
        case allow
        case allowAlways
        case deny
    }

    // MARK: - User response

    func respond(requestId: String, response: PermissionResponse) {
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        switch response {
        case .allowAlways:
            // Add rule to Claude Code settings so it never asks again
            let rule = Self.buildAllowRule(toolName: request.toolName, toolInput: request.toolInput)
            Self.addToAllowList(rule: rule)
            fallthrough
        case .allow:
            let body = "{\"decision\":\"approve\"}"
            queue.async {
                self.sendHTTPResponse(connection: request.connection, body: body)
            }
        case .deny:
            let body = "{\"decision\":\"deny\",\"reason\":\"Denied from Notch So Good\"}"
            queue.async {
                self.sendHTTPResponse(connection: request.connection, body: body)
            }
        }
    }

    // Back-compat wrapper
    func respond(requestId: String, approve: Bool) {
        respond(requestId: requestId, response: approve ? .allow : .deny)
    }

    /// Build a permission rule string for the allow list.
    /// e.g. "Edit", "Bash(git commit:*)", "mcp__pencil__batch_design"
    private static func buildAllowRule(toolName: String, toolInput: String) -> String {
        switch toolName {
        case "Bash":
            // Extract the command prefix (first word or first two words)
            let cmd = toolInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = cmd.split(separator: " ", maxSplits: 2).map(String.init)
            if let first = words.first {
                // Use first two words as prefix for common commands: "git commit:*", "npm install:*"
                let prefix = words.count >= 2 ? "\(first) \(words[1])" : first
                return "Bash(\(prefix):*)"
            }
            return "Bash"
        case "Edit", "Write", "NotebookEdit":
            // Allow the tool entirely (file-level granularity isn't useful for "always")
            return toolName
        default:
            return toolName
        }
    }

    /// Add a permission rule to ~/.claude/settings.json.
    /// Returns true on success. Invalidates the settings cache so the new rule takes effect immediately.
    @discardableResult
    private static func addToAllowList(rule: String) -> Bool {
        let path = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("PermissionServer: failed to read settings for 'Always Allow'")
            return false
        }

        var permissions = json["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []

        // Don't add duplicates
        guard !allow.contains(rule) else { return true }
        allow.append(rule)
        permissions["allow"] = allow
        json["permissions"] = permissions

        guard let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: updated, encoding: .utf8) else {
            print("PermissionServer: failed to serialize settings for 'Always Allow'")
            return false
        }

        do {
            try str.write(toFile: path, atomically: true, encoding: .utf8)
            // Invalidate cache so the new rule is picked up immediately
            cacheTimestamp = .distantPast
            return true
        } catch {
            print("PermissionServer: failed to write settings for 'Always Allow': \(error)")
            return false
        }
    }

    private func timeoutRequest(requestId: String) {
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Empty body → hook outputs nothing → Claude Code uses normal terminal flow
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        request.connection.send(
            content: response.data(using: .utf8),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in request.connection.cancel() }
        )

        DispatchQueue.main.async {
            NotificationManager.shared.windowController.dismiss()
        }
    }

    // MARK: - HTTP response

    private func sendHTTPResponse(connection: NWConnection, body: String) {
        let http = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(
            content: http.data(using: .utf8),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }
}
