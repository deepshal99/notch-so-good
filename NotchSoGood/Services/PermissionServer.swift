import Foundation

/// Unix domain socket server that receives every event from the agents' hooks.
///
/// Three events wait for an answer from the notch: `PermissionRequest` (the
/// agent is about to ask to run a tool, or to leave plan mode) and
/// `AskUserQuestion` (a multiple-choice question). Everything else reports:
/// sessions starting and ending, prompts, tools, compaction, stops and errors.
///
/// We never answer on the user's behalf. A request nobody answers, or one the
/// user hands back, gets no reply, and the agent shows its own prompt.
class PermissionServer {
    static let shared = PermissionServer()
    /// One per user: /tmp is shared between accounts.
    static let socketPath = "/tmp/notchsogood-\(getuid()).sock"
    /// Where hooks from before 4.7 send their events.
    static let legacySocketPath = "/tmp/notchsogood.sock"

    /// False when another copy of the app already owns the socket (it keeps
    /// receiving the events; this one stays quiet rather than steal them).
    private(set) var isListening = false
    /// When the last hook event arrived, for diagnostics.
    private(set) var lastEventAt: Date?

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.notchsogood.socket", qos: .userInitiated)
    /// Clients are read on a concurrent queue so one slow sender can't stall the accept loop.
    private let clientQueue = DispatchQueue(label: "com.notchsogood.socket.clients", qos: .userInitiated, attributes: .concurrent)

    struct PendingRequest {
        let id: String
        let toolName: String
        let interaction: CardInteraction
        let sessionId: String?
        let clientSocket: Int32
        let receivedAt: Date
    }

    /// Pending permission requests indexed by request ID — supports concurrent requests
    private var pendingRequests: [String: PendingRequest] = [:]
    /// Sessions whose plan was approved with "Auto-accept": a plan's approval
    /// can't switch the mode itself, so the session's next file edit does
    /// (exactly what Claude Code's own "Yes, auto-accept edits" sets).
    private var autoAcceptEdits: Set<String> = []
    private static let editTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]
    private let lock = NSLock()

    // MARK: - Payload helpers

    /// The owning app's bundle identifier, if the hook could determine one.
    /// `source_app` carries the agent name ("claude" / "codex"); older hooks put
    /// a bundle id there instead, so a dotted value is still accepted.
    static func bundleId(from json: [String: Any]) -> String? {
        if let explicit = NotchNotification.nonEmpty(json["source_bundle_id"] as? String) {
            return explicit
        }
        if let legacy = NotchNotification.nonEmpty(json["source_app"] as? String), legacy.contains(".") {
            return legacy
        }
        return nil
    }

    /// The hook process's pid. We walk its ancestry to find the terminal or IDE
    /// that owns the session — far more reliable than any env var.
    /// The long-lived process the session runs under (the terminal tab's
    /// session leader), used to find the owning app.
    /// Who is on the other end of a hook connection, asked of the kernel
    /// while the hook is still connected: the hook itself (alive exactly as
    /// long as it waits on us) and the agent above it (alive as long as the
    /// session). The agent pid is what focus and display routing walk up from,
    /// and what tells us a session ended without saying so.
    static func peer(of socket: Int32) -> (hook: pid_t, agent: pid_t?)? {
        var pid: pid_t = 0
        var len = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) == 0, pid > 1 else { return nil }
        let agent = ProcessTree.agentAncestor(of: pid)
        #if DEBUG
        NSLog("NotchSoGood: hook %d, agent %d (%@)", pid, agent ?? -1, agent.flatMap { ProcessTree.name(of: $0) } ?? "-")
        #endif
        return (pid, agent)
    }

    /// While a request waits, check once a second that its hook is still
    /// there. If the agent killed it (Escape, session closed), withdraw the
    /// card at once instead of leaving it up for two minutes.
    private func watchWaitingHook(pid: pid_t?, requestId: String) {
        guard let pid else { return }
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stillPending = self.pendingRequests[requestId] != nil
            self.lock.unlock()
            guard stillPending else { return }
            if kill(pid, 0) != 0 && errno == ESRCH {
                self.timeoutRequest(requestId: requestId)
            } else {
                self.watchWaitingHook(pid: pid, requestId: requestId)
            }
        }
    }

    // MARK: - Settings resolution

    /// Every settings file the agent itself reads, in precedence order.
    ///
    /// Project-local files matter: most people keep `permissions.allow` in the
    /// repo's `.claude/settings.local.json`, and reading only the two global
    /// files meant those rules were invisible here — so an already-allowed tool
    /// still raised a prompt in the notch.
    private static func settingsPaths(cwd: String?) -> [String] {
        var paths = [
            NSHomeDirectory() + "/.claude/settings.json",
            NSHomeDirectory() + "/.claude/settings.local.json",
        ]
        if let cwd, !cwd.isEmpty, cwd.hasPrefix("/") {
            paths.append(cwd + "/.claude/settings.json")
            paths.append(cwd + "/.claude/settings.local.json")
        }
        return paths
    }

    struct ResolvedSettings {
        var defaultMode: PermissionMode?
        var allowRules: [String] = []
    }

    // Cache per working directory — avoids re-reading four files on every call.
    private static var settingsCache: [String: (settings: ResolvedSettings, readAt: Date)] = [:]
    private static let settingsLock = NSLock()
    private static let cacheTTL: TimeInterval = 5

    static func settings(cwd: String?) -> ResolvedSettings {
        let key = cwd ?? "-"

        settingsLock.lock()
        if let hit = settingsCache[key], Date().timeIntervalSince(hit.readAt) < cacheTTL {
            settingsLock.unlock()
            return hit.settings
        }
        settingsLock.unlock()

        var resolved = ResolvedSettings()
        for path in settingsPaths(cwd: cwd) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let mode = PermissionMode.fromSettings(json) { resolved.defaultMode = mode }
            if let perms = json["permissions"] as? [String: Any],
               let allow = perms["allow"] as? [String] {
                resolved.allowRules.append(contentsOf: allow)
            }
        }

        settingsLock.lock()
        settingsCache[key] = (resolved, Date())
        settingsLock.unlock()
        return resolved
    }

    static func invalidateSettingsCache() {
        settingsLock.lock()
        settingsCache.removeAll()
        settingsLock.unlock()
    }

    /// The mode to trust for an event: the live `permission_mode` the hook sent
    /// (authoritative — the user may have flipped it with shift-tab mid-session),
    /// falling back to whatever settings declare as the default.
    static func effectiveMode(payloadMode: String?, cwd: String?) -> PermissionMode {
        if let raw = payloadMode, !raw.isEmpty, let mode = PermissionMode(rawValue: raw) {
            return mode
        }
        return settings(cwd: cwd).defaultMode ?? .standard
    }

    // MARK: - Server lifecycle

    func start() {
        queue.async { [weak self] in
            self?.startServer()
        }
    }

    private func startServer() {
        guard serverSocket < 0 else { return }

        // Another copy is already listening (a second install, a dev build):
        // leave it the events rather than silently stealing them.
        if Self.someoneListening(at: Self.socketPath) {
            NSLog("NotchSoGood: another copy is listening on %@", Self.socketPath)
            return
        }
        // A stale socket file from a crash, and the pre-4.7 shared path if it's ours.
        unlink(Self.socketPath)
        if let owner = try? FileManager.default.attributesOfItem(atPath: Self.legacySocketPath)[.ownerAccountID] as? NSNumber,
           owner.uint32Value == getuid() {
            unlink(Self.legacySocketPath)
        }

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

        // Owner-only: hooks run as the same user, and nothing else should be able
        // to drive permission decisions.
        chmod(Self.socketPath, 0o700)

        guard listen(serverSocket, 10) == 0 else {
            print("PermissionServer: failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        print("PermissionServer: listening on \(Self.socketPath)")
        isListening = true

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

    /// Whether a live server answers at `path`.
    private static func someoneListening(at path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                strcpy(UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self), ptr)
            }
        }
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if isListening { unlink(Self.socketPath) }
        isListening = false

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

        clientQueue.async { [weak self] in
            self?.handleClient(clientSocket)
        }
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
        let sessionId = NotchNotification.nonEmpty(json["session_id"] as? String)
        let cwd = NotchNotification.nonEmpty(json["cwd"] as? String)
        let sourceBundleId = Self.bundleId(from: json)
        let agentPid = Self.peer(of: clientSocket)?.agent
        let modeRaw = json["permission_mode"] as? String
        let mode = Self.effectiveMode(payloadMode: modeRaw, cwd: cwd)
        // Which agent: on every event, so a session first seen mid-flight is
        // labelled right (only SessionStart used to carry it).
        let agent = NotchNotification.nonEmpty(json["source_app"] as? String).flatMap { $0.contains(".") ? nil : $0 }
        lastEventAt = Date()

        switch event {
        case "PermissionRequest":
            handlePermissionRequest(json: json, clientSocket: clientSocket, agent: agent)

        case "AskUserQuestion":
            handleQuestion(json: json, clientSocket: clientSocket, agent: agent)

        case "PreToolUse":
            handlePreToolUse(json: json, clientSocket: clientSocket, agent: agent)

        case "PostToolUse":
            close(clientSocket)
            let toolName = json["tool_name"] as? String ?? ""
            let edited = (json["edited"] as? [String]) ?? []
            let tests = json["tests"] as? String
            let plan = (json["plan"] as? [[String: Any]]).map { $0.enumerated().compactMap { PlanStep(json: $0.element, index: $0.offset) } }
            let taskAdd = (json["task_add"] as? [String: Any]).flatMap { PlanStep(json: $0.merging(["status": "pending"]) { a, _ in a }, index: 0) }
            let taskUpdate = (json["task_update"] as? [String: Any]).map {
                PlanStep(id: $0["id"] as? String ?? "", title: $0["title"] as? String ?? "", status: $0["status"] as? String ?? "")
            }
            DispatchQueue.main.async {
                NotificationManager.shared.adoptSession(sessionId: sessionId, cwd: cwd, sourcePid: agentPid, sourceApp: agent)
                NotificationManager.shared.handlePostToolUse(sessionId: sessionId, toolName: toolName, cwd: cwd,
                                                             edited: edited, tests: tests,
                                                             plan: plan, taskAdd: taskAdd, taskUpdate: taskUpdate)
            }

        case "ReplyWait":
            // A finished Claude session listening for a reply from the notch.
            holdReply(sessionId: sessionId, clientSocket: clientSocket, hookPid: Self.peer(of: clientSocket)?.hook)

        case "PostCompact":
            close(clientSocket)
            DispatchQueue.main.async {
                NotificationManager.shared.compactionFinished(sessionId: sessionId)
            }

        case "Interrupt":
            // Codex: Esc on a running turn. It's waiting for you now.
            close(clientSocket)
            DispatchQueue.main.async {
                NotificationManager.shared.handleInterrupt(sessionId: sessionId)
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
            let source = json["source"] as? String
            DispatchQueue.main.async {
                // A SessionStart after /compact means compaction is over.
                if source == "compact" { NotificationManager.shared.compactionFinished(sessionId: sessionId) }
                NotificationManager.shared.startSession(
                    sessionId: sessionId,
                    displayName: cwd,
                    sourceBundleId: sourceBundleId,
                    sourcePid: agentPid,
                    permissionMode: mode,
                    sourceApp: sourceApp,
                    model: model
                )
            }

        case "SessionEnd":
            close(clientSocket)
            cancelReply(sessionId: sessionId)
            DispatchQueue.main.async {
                NotificationManager.shared.endSession(sessionId: sessionId)
            }

        case "Stop":
            close(clientSocket)
            if let sessionId {
                lock.lock()
                autoAcceptEdits.remove(sessionId)
                lock.unlock()
            }
            let message = json["last_assistant_message"] as? String ?? "Task completed"
            DispatchQueue.main.async {
                // Adopt first: handleNotification consults the session's mode, and
                // an unknown session would read as "standard" and prompt anyway.
                NotificationManager.shared.adoptSession(
                    sessionId: sessionId, cwd: cwd, sourceBundleId: sourceBundleId,
                    sourcePid: agentPid, permissionMode: mode, sourceApp: agent
                )
                let notification = NotchNotification(
                    type: .complete,
                    message: message,
                    sessionId: sessionId,
                    canReply: (agent ?? "claude") == "claude" && sessionId != nil && Replies.shared.supported
                )
                NotificationManager.shared.handleNotification(notification)
            }

        case "StopFailure":
            close(clientSocket)
            let error = json["error"] as? String
            let details = json["error_details"] as? String
            DispatchQueue.main.async {
                NotificationManager.shared.adoptSession(
                    sessionId: sessionId, cwd: cwd, sourceBundleId: sourceBundleId,
                    sourcePid: agentPid, permissionMode: mode, sourceApp: agent
                )
                let resetsAt = UsageLimitsStore.shared.sessionWindow(for: .claude)?.resetsAt
                let copy = StopFailure.copy(error: error, details: details,
                                            resetsIn: resetsAt.map { UsageLimitsStore.resetCountdown($0) })
                NotificationManager.shared.handleNotification(NotchNotification(
                    type: .error,
                    message: copy.message,
                    title: copy.title,
                    sessionId: sessionId
                ))
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
                NotificationManager.shared.adoptSession(
                    sessionId: sessionId, cwd: cwd, sourceBundleId: sourceBundleId,
                    sourcePid: agentPid, permissionMode: mode, sourceApp: agent
                )
                let notification = NotchNotification(
                    type: type,
                    message: message,
                    title: title,
                    sessionId: sessionId
                )
                NotificationManager.shared.handleNotification(notification)
            }

        case "UserPromptSubmit":
            close(clientSocket)
            cancelReply(sessionId: sessionId)          // they answered in the terminal
            DispatchQueue.main.async {
                NotificationManager.shared.handleUserPromptSubmit(
                    sessionId: sessionId,
                    cwd: cwd,
                    sourcePid: agentPid,
                    permissionMode: mode,
                    promptTitle: NotchNotification.clean(json["prompt_title"] as? String, limit: 80)
                )
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

    // MARK: - PreToolUse (activity only)

    /// What the agent is doing right now, for the pill. Never answered: hooks
    /// from before 4.7 that still wait get "defer" (the agent decides).
    private func handlePreToolUse(json: [String: Any], clientSocket: Int32, agent: String?) {
        let toolName = json["tool_name"] as? String ?? "Unknown"
        let toolInput = json["tool_input"] as? String ?? ""
        let sessionId = NotchNotification.nonEmpty(json["session_id"] as? String)
        let cwd = NotchNotification.nonEmpty(json["cwd"] as? String)
        let agentPid = Self.peer(of: clientSocket)?.agent
        let mode = Self.effectiveMode(payloadMode: json["permission_mode"] as? String, cwd: cwd)
        if json["decision_needed"] as? Bool == false {
            close(clientSocket)
        } else {
            sendSocketResponse(clientSocket: clientSocket, body: "{\"decision\":\"defer\"}")
        }
        let detail = toolInput.isEmpty ? nil : String(toolInput.prefix(60))
        DispatchQueue.main.async {
            NotificationManager.shared.adoptSession(sessionId: sessionId, cwd: cwd, sourcePid: agentPid, sourceApp: agent)
            NotificationManager.shared.handlePreToolUse(
                sessionId: sessionId,
                toolName: toolName,
                toolDetail: detail,
                cwd: cwd,
                sourcePid: agentPid,
                permissionMode: mode
            )
        }
    }

    // MARK: - Waiting cards (held open until the user answers)

    private func handlePermissionRequest(json: [String: Any], clientSocket: Int32, agent: String?) {
        let toolName = json["tool_name"] as? String ?? "Unknown"
        if Self.editTools.contains(toolName), let sid = NotchNotification.nonEmpty(json["session_id"] as? String) {
            lock.lock()
            let autoAccept = autoAcceptEdits.remove(sid) != nil
            lock.unlock()
            if autoAccept {
                sendSocketResponse(clientSocket: clientSocket, body: #"{"decision":"allow","mode":"acceptEdits"}"#)
                return
            }
        }
        let interaction: CardInteraction
        var detail = json["tool_input"] as? String
        if toolName == "ExitPlanMode" {
            interaction = .plan
            detail = json["plan"] as? String
        } else if let label = NotchNotification.nonEmpty(json["always_label"] as? String) {
            interaction = .permission(always: .init(label: label, destination: json["always_destination"] as? String ?? "localSettings"))
        } else {
            interaction = .permission(always: nil)
        }
        hold(json: json, clientSocket: clientSocket, agent: agent, toolName: toolName, interaction: interaction,
             detail: detail, description: json["description"] as? String)
    }

    private func handleQuestion(json: [String: Any], clientSocket: Int32, agent: String?) {
        let questions = (json["questions"] as? [[String: Any]] ?? []).compactMap(AgentQuestion.init(json:))
        guard !questions.isEmpty else { close(clientSocket); return }
        hold(json: json, clientSocket: clientSocket, agent: agent,
             toolName: NotchNotification.nonEmpty(json["tool_name"] as? String) ?? "AskUserQuestion",
             interaction: .question(Array(questions.prefix(4))), detail: nil, description: nil)
    }

    /// Keep the hook's connection open and put the card up. The answer (or a
    /// hand-back, or the 2-minute timeout) closes it.
    private func hold(json: [String: Any], clientSocket: Int32, agent: String?, toolName: String,
                      interaction: CardInteraction, detail: String?, description: String?) {
        let sessionId = NotchNotification.nonEmpty(json["session_id"] as? String)
        let cwd = NotchNotification.nonEmpty(json["cwd"] as? String)
        let peer = Self.peer(of: clientSocket)
        let mode = Self.effectiveMode(payloadMode: json["permission_mode"] as? String, cwd: cwd)
        let requestId = UUID().uuidString

        lock.lock()
        pendingRequests[requestId] = PendingRequest(
            id: requestId, toolName: toolName, interaction: interaction,
            sessionId: sessionId, clientSocket: clientSocket, receivedAt: Date()
        )
        lock.unlock()

        DispatchQueue.main.async {
            NotificationManager.shared.adoptSession(
                sessionId: sessionId, cwd: cwd, sourceBundleId: Self.bundleId(from: json),
                sourcePid: peer?.agent, permissionMode: mode, sourceApp: agent
            )
            NotificationManager.shared.showWaitingCard(
                requestId: requestId, toolName: toolName, interaction: interaction,
                detail: detail, description: description, sessionId: sessionId
            )
        }

        queue.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.timeoutRequest(requestId: requestId)
        }
        watchWaitingHook(pid: peer?.hook, requestId: requestId)
    }

    // MARK: - Replies (a finished session listening for the notch)

    private var replyWaiters: [String: Int32] = [:]

    private func holdReply(sessionId: String?, clientSocket: Int32, hookPid: pid_t?) {
        guard let sid = sessionId else { close(clientSocket); return }
        lock.lock()
        let previous = replyWaiters.updateValue(clientSocket, forKey: sid)
        lock.unlock()
        if let previous { close(previous) }
        DispatchQueue.main.async { Replies.shared.listening.insert(sid) }
        watchReplyHook(pid: hookPid, sessionId: sid, socket: clientSocket)
    }

    /// The hook dies with its session (or Claude Code times it out): stop
    /// offering a reply as soon as it's gone.
    private func watchReplyHook(pid: pid_t?, sessionId: String, socket: Int32) {
        guard let pid else { return }
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.replyWaiters[sessionId] == socket
            self.lock.unlock()
            guard current else { return }
            if kill(pid, 0) != 0 && errno == ESRCH {
                self.cancelReply(sessionId: sessionId)
            } else {
                self.watchReplyHook(pid: pid, sessionId: sessionId, socket: socket)
            }
        }
    }

    func cancelReply(sessionId: String?) {
        guard let sid = sessionId else { return }
        lock.lock()
        let socket = replyWaiters.removeValue(forKey: sid)
        lock.unlock()
        if let socket { close(socket) }
        DispatchQueue.main.async { Replies.shared.listening.remove(sid) }
    }

    /// Send a reply to a finished session; false if it isn't listening.
    @discardableResult
    func sendReply(sessionId: String, text: String) -> Bool {
        lock.lock()
        let socket = replyWaiters.removeValue(forKey: sessionId)
        lock.unlock()
        DispatchQueue.main.async { Replies.shared.listening.remove(sessionId) }
        guard let socket else { return false }
        let body = (try? JSONSerialization.data(withJSONObject: ["reply": text])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        queue.async { self.sendSocketResponse(clientSocket: socket, body: body) }
        Task { @MainActor in Telemetry.shared.trackEvent("card_answered", props: ["answer": "reply"]) }
        return true
    }

    // MARK: - Answers

    func respond(requestId: String, response: CardResponse) {
        guard let reply = response.reply else {
            handOffToTerminal(requestId: requestId)
            return
        }
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        if case .approvePlan(acceptEdits: true) = response, let sid = request.sessionId {
            lock.lock()
            autoAcceptEdits.insert(sid)
            lock.unlock()
        }
        let body = (try? JSONSerialization.data(withJSONObject: reply)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        queue.async { self.sendSocketResponse(clientSocket: request.clientSocket, body: body) }

        Task { @MainActor in
            let kind: String
            switch response {
            case .allow, .allowSession, .allowAlways: kind = "approve"
            case .deny: kind = "deny"
            case .approvePlan: kind = "plan"
            case .answer: kind = "answer"
            case .handOff: kind = "terminal"
            }
            Telemetry.shared.trackEvent("card_answered", props: ["answer": kind])
            // The session isn't blocked on us any more. PostToolUse would normally
            // flip it back to running, but denials and failed tools never send one.
            NotificationManager.shared.permissionResolved(sessionId: request.sessionId)
            NotificationManager.shared.windowController.showNextQueuedPermission()
        }
    }

    /// Get count of pending permission requests (for queue management)
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests.count
    }

    /// Whether this session has a card waiting on the user.
    func hasPending(sessionId: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests.values.contains { $0.sessionId == sessionId }
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

    // MARK: - Timeout & socket I/O

    /// Give up on answering from the notch: the hook gets no decision, so
    /// Claude Code falls back to its normal prompt in the terminal.
    func handOffToTerminal(requestId: String) {
        timeoutRequest(requestId: requestId)
    }

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
            NotificationManager.shared.permissionResolved(sessionId: request.sessionId)
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
