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
    @Published var nudgeEnabled: Bool {
        didSet { UserDefaults.standard.set(nudgeEnabled, forKey: "nudgeEnabled") }
    }
    @Published var telemetryEnabled: Bool {
        didSet { UserDefaults.standard.set(telemetryEnabled, forKey: "telemetryEnabled") }
    }
    /// Show a session's notch UI on the display its terminal is on. Off pins
    /// everything to the built-in notch screen (the old behaviour).
    @Published var followActiveDisplay: Bool {
        didSet {
            UserDefaults.standard.set(followActiveDisplay, forKey: "followActiveDisplay")
            displayCache.removeAll()
            refreshPill()
        }
    }

    /// Recent notifications, newest first (for menu bar history).
    @Published var history: [NotchNotification] = []
    private static let historyLimit = 20

    /// True when any session is waiting on the user (drives menu bar attention state).
    var needsAttention: Bool {
        activeSessions.contains { $0.status == .needsInput || $0.status == .needsPermission }
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
        var sourcePid: pid_t?        // a hook pid, for resolving the owning app by ancestry
        var cwd: String?             // working directory for window matching
        var activeToolName: String?  // currently running tool (for phase label)
        var activeToolDetail: String? // short detail about the tool (file path, command)
        var subagents: [SubagentInfo] = []
        var agentSource: AgentSource = .claude
        var permissionMode: PermissionMode = .standard
    }
    @Published var activeSessions: [SessionInfo] = []

    /// Sessions ordered by how much they need the user. The collapsed pill shows
    /// only `first`, so a session waiting on approval has to outrank one that's
    /// merely working — otherwise the notch cheerfully reports "Working" while
    /// another session sits blocked.
    var orderedSessions: [SessionInfo] {
        activeSessions.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.status.attentionPriority
                let r = rhs.element.status.attentionPriority
                if l != r { return l > r }
                return lhs.offset < rhs.offset   // stable: keep arrival order within a tier
            }
            .map(\.element)
    }

    var primarySession: SessionInfo? { orderedSessions.first }

    /// The live permission mode for a session, defaulting to standard when we
    /// have never seen an event for it.
    func permissionMode(for sessionId: String?) -> PermissionMode {
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let session = activeSessions.first(where: { $0.id == sid }) else { return .standard }
        return session.permissionMode
    }

    /// Resolved display per session. The AX query behind this is far too costly
    /// to repeat on every hook event, and the answer only changes when the user
    /// drags a window to another screen.
    private var displayCache: [String: (id: CGDirectDisplayID, at: Date)] = [:]
    private let displayCacheTTL: TimeInterval = 3

    /// Which screen a session's notch UI should appear on, or nil to use the
    /// built-in notch screen.
    func targetScreen(for session: SessionInfo?) -> NSScreen? {
        guard followActiveDisplay, let session else { return nil }

        if let hit = displayCache[session.id], Date().timeIntervalSince(hit.at) < displayCacheTTL {
            return NotchGeometry.screen(withDisplayID: hit.id)
        }
        guard let screen = DisplayRouter.screen(
            sourcePid: session.sourcePid,
            sourceBundleId: session.sourceBundleId
        ) else { return nil }

        displayCache[session.id] = (screen.displayID, Date())
        return screen
    }

    /// Display arrangement changed — every cached answer is suspect.
    func invalidateDisplayCache() {
        displayCache.removeAll()
    }

    private var endSessionWorkItems: [String: DispatchWorkItem] = [:]
    private var sessionTimeoutTimers: [String: Timer] = [:]
    private let sessionTimeoutInterval: TimeInterval = 3600 // 1 hour without any activity
    private var nudgeTimers: [String: Timer] = [:]
    private let nudgeInterval: TimeInterval = 120

    // Anti-spam: Claude Code re-fires idle/permission Notification events every
    // ~60s while waiting. Without this, every re-fire is a fresh popup + sound.
    private var lastPopupAt: [String: Date] = [:]      // "sid|type" -> last time we showed it
    private var mutedKeys: Set<String> = []            // muted after the user addressed one
    private let repeatPopupCooldown: TimeInterval = 180
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
        if defaults.object(forKey: "nudgeEnabled") == nil {
            defaults.set(true, forKey: "nudgeEnabled")
        }
        if defaults.object(forKey: "telemetryEnabled") == nil {
            defaults.set(true, forKey: "telemetryEnabled")
        }
        if defaults.object(forKey: "followActiveDisplay") == nil {
            defaults.set(true, forKey: "followActiveDisplay")
        }

        soundEnabled = defaults.bool(forKey: "soundEnabled")
        showOnComplete = defaults.bool(forKey: "showOnComplete")
        showOnQuestion = defaults.bool(forKey: "showOnQuestion")
        showOnPermission = defaults.bool(forKey: "showOnPermission")
        showSessionPill = defaults.bool(forKey: "showSessionPill")
        nudgeEnabled = defaults.bool(forKey: "nudgeEnabled")
        telemetryEnabled = defaults.bool(forKey: "telemetryEnabled")
        followActiveDisplay = defaults.bool(forKey: "followActiveDisplay")

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

    /// Single ingress for every hook event.
    ///
    /// Creates the session if we've never seen it — the app may have launched
    /// mid-session, or SessionStart may have been missed — and otherwise merges
    /// in whatever metadata this event carries. Previously every handler bailed
    /// out on an unknown session id, so a session that started before the app
    /// did stayed invisible and all its status updates were silently dropped.
    ///
    /// Sessions are tracked even when the pill is switched off: the menu bar
    /// card, the attention dot and permission routing all depend on this state.
    @discardableResult
    func adoptSession(
        sessionId: String?,
        cwd: String? = nil,
        sourceBundleId: String? = nil,
        sourcePid: pid_t? = nil,
        permissionMode: PermissionMode? = nil,
        sourceApp: String? = nil,
        model: String? = nil
    ) -> Int? {
        guard let sid = NotchNotification.nonEmpty(sessionId) else { return nil }

        // Cancel any pending end for this session
        endSessionWorkItems[sid]?.cancel()
        endSessionWorkItems.removeValue(forKey: sid)

        let resolvedCwd = NotchNotification.nonEmpty(cwd)

        if let idx = activeSessions.firstIndex(where: { $0.id == sid }) {
            if let resolvedCwd {
                activeSessions[idx].cwd = resolvedCwd
                activeSessions[idx].projectName = sanitizedProjectName(resolvedCwd, sessionId: sid)
            }
            if let bundleId = NotchNotification.nonEmpty(sourceBundleId) {
                activeSessions[idx].sourceBundleId = bundleId
            }
            if let sourcePid, sourcePid > 0 {
                activeSessions[idx].sourcePid = sourcePid
            }
            if let permissionMode {
                activeSessions[idx].permissionMode = permissionMode
            }
            // Only overwrite the agent when this event actually identifies one —
            // detect() defaults to .claude, which would clobber a known Codex session.
            if sourceApp != nil || model != nil {
                activeSessions[idx].agentSource = AgentSource.detect(sourceApp: sourceApp, model: model)
            }
            resetSessionTimeout(sessionId: sid)
            return idx
        }

        var session = SessionInfo(
            id: sid,
            startTime: Date(),
            projectName: sanitizedProjectName(resolvedCwd, sessionId: sid),
            status: .running,
            sourceBundleId: NotchNotification.nonEmpty(sourceBundleId),
            sourcePid: sourcePid,
            cwd: resolvedCwd,
            agentSource: AgentSource.detect(sourceApp: sourceApp, model: model)
        )
        if let permissionMode { session.permissionMode = permissionMode }
        activeSessions.append(session)
        StatsStore.shared.recordSessionStarted()

        // Start watching JSONL file for interrupts
        SessionFileWatcher.shared.startWatching(sessionId: sid, cwd: resolvedCwd)

        // Safety timeout — auto-end session after 1 hour of silence to prevent zombie pills
        resetSessionTimeout(sessionId: sid)
        return activeSessions.count - 1
    }

    func startSession(
        sessionId: String?,
        displayName: String? = nil,
        sourceBundleId: String? = nil,
        sourcePid: pid_t? = nil,
        permissionMode: PermissionMode? = nil,
        sourceApp: String? = nil,
        model: String? = nil
    ) {
        adoptSession(
            sessionId: sessionId ?? UUID().uuidString,
            cwd: displayName,
            sourceBundleId: sourceBundleId,
            sourcePid: sourcePid,
            permissionMode: permissionMode,
            sourceApp: sourceApp,
            model: model
        )
        refreshPill()
    }

    /// (Re)arm the zombie-pill timeout. Called on every event so long active sessions survive.
    private func resetSessionTimeout(sessionId sid: String) {
        sessionTimeoutTimers[sid]?.invalidate()
        sessionTimeoutTimers[sid] = Timer.scheduledTimer(withTimeInterval: sessionTimeoutInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.endSession(sessionId: sid)
            }
        }
    }

    /// End exactly one session. A missing or empty id is ignored rather than
    /// treated as "end everything" — hooks send `""` for unknown fields, and one
    /// malformed SessionEnd used to be able to wipe every tracked session.
    func endSession(sessionId: String?) {
        guard let sid = NotchNotification.nonEmpty(sessionId) else { return }

        if let session = activeSessions.first(where: { $0.id == sid }) {
            StatsStore.shared.recordActiveSeconds(Date().timeIntervalSince(session.startTime))
        }
        activeSessions.removeAll { $0.id == sid }
        endSessionWorkItems.removeValue(forKey: sid)
        sessionTimeoutTimers[sid]?.invalidate()
        sessionTimeoutTimers.removeValue(forKey: sid)
        nudgeTimers[sid]?.invalidate()
        nudgeTimers.removeValue(forKey: sid)
        clearPopupState(sessionId: sid)
        displayCache.removeValue(forKey: sid)
        SessionFileWatcher.shared.stopWatching(sessionId: sid)

        if activeSessions.isEmpty {
            windowController.hideSessionPill()
        } else {
            refreshPill()
        }
    }

    private func refreshPill() {
        guard showSessionPill, let primary = primarySession else {
            if windowController.isShowingPill { windowController.hideSessionPill() }
            return
        }
        windowController.showSessionPill(
            sessions: orderedSessions,
            primaryStartTime: primary.startTime,
            screen: targetScreen(for: primary)
        )
    }

    var hasActiveSession: Bool {
        !activeSessions.isEmpty
    }

    // Back-compat helpers
    var activeSessionId: String? { primarySession?.id }
    var sessionStartTime: Date? { primarySession?.startTime }

    // MARK: - Notifications

    func updateSessionStatus(sessionId: String?, status: SessionStatus, message: String? = nil) {
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let idx = adoptSession(sessionId: sid) else { return }
        let oldStatus = activeSessions[idx].status
        let wasCompleted = oldStatus == .completed
        activeSessions[idx].status = status
        // Session moved on — the previous waiting spell is over, unmute its alerts
        if status == .running || status == .completed {
            clearPopupState(sessionId: sid)
        }
        if status == .completed && !wasCompleted {
            StatsStore.shared.recordTaskCompleted()
            Telemetry.shared.trackEvent("session_completed")
        }
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
        resetSessionTimeout(sessionId: sid)
        // Only arm the nudge when ENTERING a waiting state — repeated same-status
        // events (Claude re-fires them every minute) must not re-arm it.
        if oldStatus != status {
            scheduleNudgeIfNeeded(sessionId: sid, status: status)
        }
        refreshPill()
    }

    // MARK: - Popup dedupe / mute

    private func popupKey(_ sessionId: String?, _ type: NotificationType) -> String {
        "\(sessionId ?? "-")|\(type.rawValue)"
    }

    private func clearPopupState(sessionId: String) {
        mutedKeys = mutedKeys.filter { !$0.hasPrefix("\(sessionId)|") }
        lastPopupAt = lastPopupAt.filter { !$0.key.hasPrefix("\(sessionId)|") }
    }

    /// User clicked or explicitly dismissed a popup — stay quiet about this
    /// session+type until the session actually moves on.
    func muteRepeats(sessionId: String?, type: NotificationType) {
        mutedKeys.insert(popupKey(sessionId, type))
    }

    /// A permission request was answered (or timed out) — the session is running
    /// again, not waiting on us. Without this the row stayed "Needs approval"
    /// forever whenever no PostToolUse followed: denials, interrupts, and tools
    /// that error out never send one.
    func permissionResolved(sessionId: String?) {
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }
        if activeSessions[idx].status == .needsPermission {
            activeSessions[idx].status = .running
        }
        nudgeTimers[sid]?.invalidate()
        nudgeTimers.removeValue(forKey: sid)
        clearPopupState(sessionId: sid)
        refreshPill()
    }

    /// Should this popup be suppressed as a repeat of one already shown/addressed?
    private func isRepeatPopup(_ notification: NotchNotification) -> Bool {
        // Interactive permission cards are always distinct real requests
        guard !notification.isInteractivePermission else { return false }
        let key = popupKey(notification.sessionId, notification.type)
        if mutedKeys.contains(key) { return true }
        if let last = lastPopupAt[key], Date().timeIntervalSince(last) < repeatPopupCooldown {
            return true
        }
        return false
    }

    // MARK: - Nudge (gentle re-alert when a session waits too long)

    private func scheduleNudgeIfNeeded(sessionId sid: String, status: SessionStatus) {
        nudgeTimers[sid]?.invalidate()
        nudgeTimers.removeValue(forKey: sid)
        guard nudgeEnabled, status == .needsInput || status == .needsPermission else { return }

        nudgeTimers[sid] = Timer.scheduledTimer(withTimeInterval: nudgeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let session = self.activeSessions.first(where: { $0.id == sid }),
                      session.status == .needsInput || session.status == .needsPermission else { return }
                let notification = NotchNotification(
                    type: .general,
                    message: "Still waiting on you — \(session.projectName)",
                    title: "Psst",
                    sessionId: sid
                )
                self.windowController.showNotification(
                    notification,
                    sessionSourceBundleId: session.sourceBundleId,
                    sessionCwd: session.cwd,
                    sessionSourcePid: session.sourcePid,
                    screen: self.targetScreen(for: session)
                )
            }
        }
    }

    func handleNotification(_ notification: NotchNotification) {
        // A session whose agent decides for itself (bypass / auto / plan) never
        // needs a permission gate from us. Claude Code still fires its own
        // Notification event in those modes, and echoing it here is the
        // double-prompt users see after switching to bypass mode.
        if notification.type == .permission,
           permissionMode(for: notification.sessionId).suppressesPrompts {
            return
        }

        let isRepeat = isRepeatPopup(notification)
        if !isRepeat {
            recordHistory(notification)
        }

        // Track the session even if we missed its SessionStart
        if notification.sessionId != nil {
            adoptSession(sessionId: notification.sessionId)
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

        // Suppress repeats of an alert the user has already seen or addressed
        guard !isRepeat else { return }

        // A hook-level permission event while our interactive card is up (or queued)
        // would double-alert for the same approval — the card already covers it.
        if notification.type == .permission,
           !notification.isInteractivePermission,
           PermissionServer.shared.pendingCount > 0 {
            return
        }

        lastPopupAt[popupKey(notification.sessionId, notification.type)] = Date()

        let session = activeSessions.first(where: { $0.id == notification.sessionId })
        Telemetry.shared.trackEvent("notification_shown", props: ["type": notification.type.rawValue])
        windowController.showNotification(
            notification,
            sessionSourceBundleId: session?.sourceBundleId,
            sessionCwd: session?.cwd,
            sessionSourcePid: session?.sourcePid,
            screen: targetScreen(for: session)
        )

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

    /// Append to menu bar history, newest first.
    private func recordHistory(_ notification: NotchNotification) {
        history.insert(notification, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    /// PreToolUse: tool about to run — track active tool name for phase label
    func handlePreToolUse(
        sessionId: String?,
        toolName: String,
        toolDetail: String?,
        cwd: String? = nil,
        sourcePid: pid_t? = nil,
        permissionMode: PermissionMode? = nil
    ) {
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let idx = adoptSession(
                sessionId: sid,
                cwd: cwd,
                sourcePid: sourcePid,
                permissionMode: permissionMode
              ) else { return }
        activeSessions[idx].activeToolName = toolName
        activeSessions[idx].activeToolDetail = toolDetail
        if activeSessions[idx].status != .needsPermission {
            activeSessions[idx].status = .running
        }
        refreshPill()
    }

    /// PostToolUse: tool finished running — clear active tool, update status
    func handlePostToolUse(sessionId: String?, toolName: String, cwd: String? = nil) {
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let idx = adoptSession(sessionId: sid, cwd: cwd) else { return }
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
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let idx = adoptSession(sessionId: sid) else { return }
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
        guard let sid = NotchNotification.nonEmpty(sessionId),
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
    func handleUserPromptSubmit(
        sessionId: String?,
        cwd: String? = nil,
        sourcePid: pid_t? = nil,
        permissionMode: PermissionMode? = nil
    ) {
        guard let sid = NotchNotification.nonEmpty(sessionId),
              let idx = adoptSession(
                sessionId: sid,
                cwd: cwd,
                sourcePid: sourcePid,
                permissionMode: permissionMode
              ) else { return }

        // New user turn — clear previous tool state and any popup mutes
        activeSessions[idx].activeToolName = nil
        activeSessions[idx].activeToolDetail = nil
        clearPopupState(sessionId: sid)

        updateSessionStatus(sessionId: sid, status: .running)
    }

    // MARK: - Auto-setup

    /// Bump when the hook bridge's wire format or command line changes, so an
    /// upgrade reinstalls hooks even if the app version didn't move.
    private static let hooksSchemaVersion = 2

    /// Install hooks on first launch, on version updates, and whenever the hook
    /// bridge itself changes shape.
    func installHooksIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let stamp = "\(currentVersion)#\(Self.hooksSchemaVersion)"
        let installed = UserDefaults.standard.string(forKey: "hooksInstalledVersion") ?? ""

        if installed != stamp {
            installHooks()
            UserDefaults.standard.set(stamp, forKey: "hooksInstalledVersion")
        }
    }

    func installHooks() {
        let bundle = Bundle.main
        // Install Claude Code hooks
        if let script = bundle.path(forResource: "install-hooks", ofType: "sh") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [script]
            try? task.run()
        }
        // Install Codex CLI hooks
        if let script = bundle.path(forResource: "install-codex-hooks", ofType: "sh") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [script]
            try? task.run()
        }
    }

    // MARK: - Permission requests (from PermissionServer)

    func showPermissionRequest(requestId: String, toolName: String, toolInput: String, sessionId: String?) {
        let (action, detail) = Self.sanitizePermission(toolName: toolName, toolInput: toolInput)

        // Belt and braces: the server already filters these out, but never let a
        // bypass/auto/plan session get a blocking prompt, and never mark it as
        // "needs approval" — it doesn't.
        if permissionMode(for: sessionId).autoApproves(toolName: toolName) {
            PermissionServer.shared.respond(requestId: requestId, approve: true)
            return
        }

        guard showOnPermission else {
            // If permission notifications are disabled, auto-approve
            PermissionServer.shared.respond(requestId: requestId, approve: true)
            return
        }

        // Only now is the session genuinely blocked on the user
        if sessionId != nil {
            updateSessionStatus(sessionId: sessionId, status: .needsPermission, message: action)
        }

        let notification = NotchNotification(
            type: .permission,
            message: detail,
            title: action,
            sessionId: sessionId,
            permissionRequestId: requestId,
            toolName: toolName
        )
        recordHistory(notification)

        let session = activeSessions.first(where: { $0.id == sessionId })
        Telemetry.shared.trackEvent("notification_shown", props: ["type": notification.type.rawValue])
        windowController.showNotification(
            notification,
            sessionSourceBundleId: session?.sourceBundleId,
            sessionCwd: session?.cwd,
            sessionSourcePid: session?.sourcePid,
            screen: targetScreen(for: session)
        )
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
