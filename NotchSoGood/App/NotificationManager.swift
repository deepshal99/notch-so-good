import Foundation
import AppKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
            SoundManager.shared.isEnabled = soundEnabled
        }
    }
    @Published var showOnComplete: Bool {
        didSet { UserDefaults.standard.set(showOnComplete, forKey: "showOnComplete") }
    }
    @Published var showOnQuestion: Bool {
        didSet { UserDefaults.standard.set(showOnQuestion, forKey: "showOnQuestion") }
    }
    @Published var showOnPermission: Bool {
        didSet { UserDefaults.standard.set(showOnPermission, forKey: "showOnPermission") }
    }
    @Published var showSessionPill: Bool {
        didSet {
            UserDefaults.standard.set(showSessionPill, forKey: "showSessionPill")
            if !showSessionPill {
                windowController.hideSessionPill()
            } else if hasActiveSession {
                refreshPill()
            }
        }
    }

    // Active session tracking — supports multiple concurrent sessions
    struct SubagentInfo: Identifiable {
        let id: String             // subagent/task ID
        let parentSessionId: String
        var description: String    // short task description
        var status: SessionStatus
        let startTime: Date
    }

    struct SessionInfo: Identifiable {
        let id: String
        let startTime: Date
        var projectName: String   // sanitized cwd or short UUID fallback
        var status: SessionStatus
        var lastMessage: String?
        var sourceBundleId: String?  // bundle ID of the terminal/IDE that owns this session
        var cwd: String?             // working directory for window matching
        var activeToolName: String?  // currently running tool (for phase label)
        var activeToolDetail: String? // short detail about the tool (file path, command)
        var subagents: [SubagentInfo] = []
    }
    @Published var activeSessions: [SessionInfo] = []

    private var endSessionWorkItems: [String: DispatchWorkItem] = [:]
    private var sessionTimeoutTimers: [String: Timer] = [:]
    private let sessionTimeoutInterval: TimeInterval = 3600 // 1 hour max session
    let windowController = NotchWindowController()

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "soundEnabled") == nil {
            defaults.set(true, forKey: "soundEnabled")
        }
        if defaults.object(forKey: "showOnComplete") == nil {
            defaults.set(true, forKey: "showOnComplete")
        }
        if defaults.object(forKey: "showOnQuestion") == nil {
            defaults.set(true, forKey: "showOnQuestion")
        }
        if defaults.object(forKey: "showOnPermission") == nil {
            defaults.set(true, forKey: "showOnPermission")
        }
        if defaults.object(forKey: "showSessionPill") == nil {
            defaults.set(true, forKey: "showSessionPill")
        }

        soundEnabled = defaults.bool(forKey: "soundEnabled")
        showOnComplete = defaults.bool(forKey: "showOnComplete")
        showOnQuestion = defaults.bool(forKey: "showOnQuestion")
        showOnPermission = defaults.bool(forKey: "showOnPermission")
        showSessionPill = defaults.bool(forKey: "showSessionPill")

        SoundManager.shared.isEnabled = soundEnabled
    }

    // MARK: - Session lifecycle

    // Names that aren't useful as session labels
    private static let unhelpfulNames: Set<String> = [
        "/", "~", "tmp", "var", "etc", "usr", "bin", "opt", "home", "root",
        "Desktop", "Documents", "Downloads",
    ]

    // Generic container folders that shouldn't appear as parent context
    private static let genericParents: Set<String> = [
        "Documents", "Desktop", "Downloads", "Projects", "repos", "Repos",
        "code", "Code", "dev", "Dev", "src", "workspace", "workspaces",
        "Workspace", "Workspaces", "Sites", "sites", "home", "Home",
        "Users", "tmp", "var", "opt",
    ]

    private func sanitizedProjectName(_ raw: String?, sessionId: String) -> String {
        guard let raw, !raw.isEmpty else {
            return String(sessionId.prefix(6))
        }
        // Walk up from the last component, skipping generic/unhelpful folders
        let components = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let home = NSHomeDirectory()
        let homeBase = (home as NSString).lastPathComponent

        // Get the project folder (last component)
        guard let project = components.last,
              !Self.unhelpfulNames.contains(project),
              project != homeBase else {
            return String(sessionId.prefix(6))
        }

        // Find a meaningful parent (skip generic containers)
        if components.count >= 2 {
            let parent = components[components.count - 2]
            if !Self.genericParents.contains(parent) && parent != homeBase {
                return "\(parent) / \(project)"
            }
        }

        return project
    }

    func startSession(sessionId: String?, displayName: String? = nil, sourceBundleId: String? = nil) {
        guard showSessionPill else { return }

        let sid = sessionId ?? UUID().uuidString

        // Cancel any pending end for this session
        endSessionWorkItems[sid]?.cancel()
        endSessionWorkItems.removeValue(forKey: sid)

        // Don't add duplicate — but update project name and source app if we now have them
        if let idx = activeSessions.firstIndex(where: { $0.id == sid }) {
            if let name = displayName {
                activeSessions[idx].projectName = sanitizedProjectName(name, sessionId: sid)
            }
            if let bundleId = sourceBundleId, !bundleId.isEmpty {
                activeSessions[idx].sourceBundleId = bundleId
            }
            if let cwd = displayName, !cwd.isEmpty {
                activeSessions[idx].cwd = cwd
            }
            refreshPill()
            return
        }

        let project = sanitizedProjectName(displayName, sessionId: sid)
        activeSessions.append(SessionInfo(id: sid, startTime: Date(), projectName: project, status: .running, sourceBundleId: sourceBundleId, cwd: displayName))
        refreshPill()

        // Start watching JSONL file for interrupts
        SessionFileWatcher.shared.startWatching(sessionId: sid, cwd: displayName)

        // Safety timeout — auto-end session after 1 hour to prevent zombie pills
        sessionTimeoutTimers[sid]?.invalidate()
        sessionTimeoutTimers[sid] = Timer.scheduledTimer(withTimeInterval: sessionTimeoutInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.endSession(sessionId: sid)
            }
        }
    }

    func endSession(sessionId: String?) {
        if let sid = sessionId {
            activeSessions.removeAll { $0.id == sid }
            endSessionWorkItems.removeValue(forKey: sid)
            sessionTimeoutTimers[sid]?.invalidate()
            sessionTimeoutTimers.removeValue(forKey: sid)
            SessionFileWatcher.shared.stopWatching(sessionId: sid)
        } else {
            // No ID — end all sessions
            activeSessions.removeAll()
            endSessionWorkItems.removeAll()
            sessionTimeoutTimers.values.forEach { $0.invalidate() }
            sessionTimeoutTimers.removeAll()
            SessionFileWatcher.shared.stopAll()
        }

        if activeSessions.isEmpty {
            windowController.hideSessionPill()
        } else {
            refreshPill()
        }
    }

    private func refreshPill() {
        guard let first = activeSessions.first else { return }
        windowController.showSessionPill(sessions: activeSessions, primaryStartTime: first.startTime)
    }

    var hasActiveSession: Bool {
        !activeSessions.isEmpty
    }

    // Back-compat helpers
    var activeSessionId: String? { activeSessions.first?.id }
    var sessionStartTime: Date? { activeSessions.first?.startTime }

    // MARK: - Notifications

    func updateSessionStatus(sessionId: String?, status: SessionStatus, message: String? = nil) {
        guard let sid = sessionId,
              let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }
        activeSessions[idx].status = status
        if let msg = message {
            activeSessions[idx].lastMessage = msg
        }
        // Clear transient state when session completes or goes idle
        if status == .completed || status == .needsInput {
            activeSessions[idx].activeToolName = nil
            activeSessions[idx].activeToolDetail = nil
        }
        if status == .completed {
            activeSessions[idx].subagents.removeAll()
        }
        refreshPill()
    }

    func handleNotification(_ notification: NotchNotification) {
        // Auto-start session pill if not already showing
        if !hasActiveSession && showSessionPill {
            startSession(sessionId: notification.sessionId)
        }

        // Update session status based on notification type
        if let sid = notification.sessionId {
            switch notification.type {
            case .question:
                updateSessionStatus(sessionId: sid, status: .needsInput, message: notification.message)
            case .permission:
                updateSessionStatus(sessionId: sid, status: .needsPermission, message: notification.message)
            case .complete:
                updateSessionStatus(sessionId: sid, status: .completed, message: notification.message)
            case .general:
                break
            }
        }

        switch notification.type {
        case .complete:
            guard showOnComplete else { return }
        case .question:
            guard showOnQuestion else { return }
        case .permission:
            guard showOnPermission else { return }
        case .general:
            break
        }

        let session = activeSessions.first(where: { $0.id == notification.sessionId })
        windowController.showNotification(notification, sessionSourceBundleId: session?.sourceBundleId, sessionCwd: session?.cwd)

        // Session end is handled by the SessionEnd hook — no auto-end timer needed.
        // The pill stays visible (showing "Done") until SessionEnd arrives.
    }

    func showTestNotification(type: NotificationType) {
        let messages: [NotificationType: String] = [
            .complete: "Finished implementing the notification system!",
            .question: "Should I refactor the animation module?",
            .permission: "Claude wants to edit AppDelegate.swift",
            .general: "Hey! Claude Code is ready for you",
        ]

        let notification = NotchNotification(
            type: type,
            message: messages[type] ?? "Test notification",
            title: nil,
            sessionId: "test-session",
            sourceBundleId: nil
        )

        // Start a test session pill too
        if !hasActiveSession {
            startSession(sessionId: "test-session", displayName: "Test Project")
        }

        windowController.showNotification(notification)

        // For test sessions, auto-end after 8s since there's no real SessionEnd hook
        if type == .complete {
            let sid = "test-session"
            endSessionWorkItems[sid]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.endSession(sessionId: sid)
            }
            endSessionWorkItems[sid] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
        }
    }

    // MARK: - New event handlers (from socket server)

    /// PreToolUse: tool about to run — track active tool name for phase label
    func handlePreToolUse(sessionId: String?, toolName: String, toolDetail: String?) {
        guard let sid = sessionId,
              let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }
        activeSessions[idx].activeToolName = toolName
        activeSessions[idx].activeToolDetail = toolDetail
        if activeSessions[idx].status != .needsPermission {
            activeSessions[idx].status = .running
        }
        refreshPill()
    }

    /// PostToolUse: tool finished running — clear active tool, update status
    func handlePostToolUse(sessionId: String?, toolName: String) {
        guard let sid = sessionId,
              let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }
        activeSessions[idx].activeToolName = nil
        activeSessions[idx].activeToolDetail = nil
        let current = activeSessions[idx].status
        if current == .needsPermission || current == .compacting {
            activeSessions[idx].status = .running
        }
        refreshPill()
    }

    /// SubagentStart: a subagent was spawned
    func handleSubagentStart(sessionId: String?, subagentId: String?, description: String?) {
        guard let sid = sessionId,
              let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }
        let agentId = subagentId ?? UUID().uuidString
        // Don't add duplicates
        if activeSessions[idx].subagents.contains(where: { $0.id == agentId }) { return }
        let sub = SubagentInfo(
            id: agentId,
            parentSessionId: sid,
            description: description ?? "Agent task",
            status: .running,
            startTime: Date()
        )
        activeSessions[idx].subagents.append(sub)
        refreshPill()
    }

    /// SubagentStop: a subagent finished
    func handleSubagentStop(sessionId: String?, subagentId: String?) {
        guard let sid = sessionId,
              let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }
        if let subId = subagentId,
           let subIdx = activeSessions[idx].subagents.firstIndex(where: { $0.id == subId }) {
            activeSessions[idx].subagents[subIdx].status = .completed
        }
        // Remove completed subagents after a brief delay
        let capturedSid = sid
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let idx = self.activeSessions.firstIndex(where: { $0.id == capturedSid }) else { return }
            self.activeSessions[idx].subagents.removeAll { $0.status == .completed }
            self.refreshPill()
        }
        refreshPill()
    }

    /// UserPromptSubmit: user sent a message — session is active, clear stale tool state
    func handleUserPromptSubmit(sessionId: String?) {
        guard let sid = sessionId else { return }

        // Auto-start session if needed
        if !activeSessions.contains(where: { $0.id == sid }) && showSessionPill {
            startSession(sessionId: sid)
        }

        // New user turn — clear previous tool state
        if let idx = activeSessions.firstIndex(where: { $0.id == sid }) {
            activeSessions[idx].activeToolName = nil
            activeSessions[idx].activeToolDetail = nil
        }

        updateSessionStatus(sessionId: sid, status: .running)
    }

    // MARK: - Auto-setup

    /// Install hooks on first launch and on every version update (so new hooks like PreToolUse get added).
    func installHooksIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let installedVersion = UserDefaults.standard.string(forKey: "hooksInstalledVersion") ?? ""

        if installedVersion != currentVersion {
            installHooks()
            UserDefaults.standard.set(currentVersion, forKey: "hooksInstalledVersion")
        }
    }

    func installHooks() {
        let bundle = Bundle.main
        if let script = bundle.path(forResource: "install-hooks", ofType: "sh") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [script]
            try? task.run()
        }
    }

    // MARK: - Permission requests (from PermissionServer)

    func showPermissionRequest(requestId: String, toolName: String, toolInput: String, sessionId: String?) {
        let (action, detail) = Self.sanitizePermission(toolName: toolName, toolInput: toolInput)

        // Update session status
        if let sid = sessionId {
            updateSessionStatus(sessionId: sid, status: .needsPermission, message: action)
        }

        guard showOnPermission else {
            // If permission notifications are disabled, auto-approve
            PermissionServer.shared.respond(requestId: requestId, approve: true)
            return
        }

        let notification = NotchNotification(
            type: .permission,
            message: detail,
            title: action,
            sessionId: sessionId,
            permissionRequestId: requestId,
            toolName: toolName
        )

        let session = activeSessions.first(where: { $0.id == sessionId })
        windowController.showNotification(notification, sessionSourceBundleId: session?.sourceBundleId, sessionCwd: session?.cwd)
    }

    // MARK: - Permission sanitization

    /// Returns a human-readable (action, detail) pair for a tool permission request.
    /// Action = short verb phrase for the title, Detail = the most useful context.
    static func sanitizePermission(toolName: String, toolInput: String) -> (action: String, detail: String) {
        switch toolName {
        case "Bash":
            let cmd = toolInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = Self.shortCommand(cmd)
            return ("Run command", short)

        case "Edit":
            return ("Edit file", Self.shortPath(toolInput))

        case "Write":
            return ("Create file", Self.shortPath(toolInput))

        case "NotebookEdit":
            return ("Edit notebook", Self.shortPath(toolInput))

        case "CronCreate":
            return ("Create cron job", toolInput.isEmpty ? "Scheduled task" : String(toolInput.prefix(80)))

        case "CronDelete":
            return ("Delete cron job", toolInput.isEmpty ? "Scheduled task" : String(toolInput.prefix(80)))

        default:
            // MCP write tools or unknown
            let friendly = Self.friendlyMcpName(toolName)
            let detail = toolInput.isEmpty ? "Waiting for approval" : String(toolInput.prefix(100))
            return (friendly, detail)
        }
    }

    /// Extract just the meaningful command from a potentially long bash string.
    /// "cd /long/path && git commit -m 'foo'" → "git commit -m 'foo'"
    /// "INPUT=$(cat); eval ..." → first recognizable command
    private static func shortCommand(_ raw: String) -> String {
        let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return "Terminal command" }

        // If the input looks like raw JSON (hook sent unsanitized data), extract something useful
        if cmd.hasPrefix("{") || cmd.contains("\"tool_name\"") || cmd.contains("\"tool_input\"") {
            return "Terminal command"
        }

        // Split on && or ; and take the last meaningful segment
        let segments = cmd.components(separatedBy: "&&")
            .flatMap { $0.components(separatedBy: ";") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { seg in
                let lower = seg.lowercased()
                // Skip noise: cd, variable assignments, echo of JSON, pipe chains
                return !seg.isEmpty
                    && !lower.hasPrefix("cd ")
                    && !lower.hasPrefix("input=")
                    && !lower.hasPrefix("eval ")
                    && !lower.hasPrefix("export ")
                    && !lower.hasPrefix("echo '{")
                    && !lower.hasPrefix("echo \"{")
                    && !(lower.hasPrefix("echo ") && lower.contains("tool_name"))
            }

        let best = segments.last ?? "Terminal command"

        // If we filtered everything out, show generic
        if best == cmd && best.count > 100 {
            // Try to get first word as the command name
            let firstWord = best.split(separator: " ").first.map(String.init) ?? "Terminal command"
            return firstWord
        }

        // Truncate long commands but keep enough context
        if best.count > 80 {
            return String(best.prefix(77)) + "..."
        }
        return best
    }

    /// "/Users/foo/project/src/Views/MyView.swift" → "MyView.swift"
    /// or "src/Views/MyView.swift" if short enough
    private static func shortPath(_ raw: String) -> String {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "Unknown file" }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let filename = components.last else { return path }

        // If 3 or fewer components, show as-is
        if components.count <= 3 {
            return path
        }

        // Show last 2 components for context: "Views/MyView.swift"
        if components.count >= 2 {
            let parent = components[components.count - 2]
            return "\(parent)/\(filename)"
        }

        return String(filename)
    }

    /// "mcp__pencil__batch_design" → "Design update"
    /// "mcp__conductor__SomeAction" → "Some Action"
    private static func friendlyMcpName(_ toolName: String) -> String {
        // Known MCP tool friendly names
        let known: [String: String] = [
            "mcp__pencil__batch_design": "Design update",
            "mcp__pencil__open_document": "Open document",
            "mcp__pencil__set_variables": "Set design variables",
            "mcp__pencil__replace_all_matching_properties": "Replace design properties",
            "mcp__pencil__export_nodes": "Export design",
            "mcp__agentation__agentation_reply": "Send reply",
            "mcp__agentation__agentation_resolve": "Resolve request",
            "mcp__agentation__agentation_acknowledge": "Acknowledge",
            "mcp__agentation__agentation_dismiss": "Dismiss",
        ]
        if let friendly = known[toolName] { return friendly }

        // Generic: strip mcp__ prefix, replace underscores with spaces, capitalize
        var name = toolName
        if name.hasPrefix("mcp__") {
            // "mcp__foo__bar_baz" → "bar baz"
            let parts = name.split(separator: "__", omittingEmptySubsequences: true)
            name = parts.count >= 3 ? String(parts[2...].joined(separator: " ")) :
                   parts.count >= 2 ? String(parts.last!) : name
        }
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
