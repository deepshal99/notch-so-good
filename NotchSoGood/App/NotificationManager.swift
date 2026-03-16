import Foundation
import AppKit

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
    struct SessionInfo: Identifiable {
        let id: String
        let startTime: Date
        var displayName: String
        var status: SessionStatus
        var lastMessage: String?
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

    func startSession(sessionId: String?, displayName: String? = nil) {
        guard showSessionPill else { return }

        let sid = sessionId ?? UUID().uuidString

        // Cancel any pending end for this session
        endSessionWorkItems[sid]?.cancel()
        endSessionWorkItems.removeValue(forKey: sid)

        // Don't add duplicate — but update name if we now have one
        if let idx = activeSessions.firstIndex(where: { $0.id == sid }) {
            if let name = displayName, !name.isEmpty {
                activeSessions[idx].displayName = name
            }
            // Reset status back to running on re-start
            activeSessions[idx].status = .running
            refreshPill()
            return
        }

        let name = displayName ?? String(sid.prefix(6))
        activeSessions.append(SessionInfo(id: sid, startTime: Date(), displayName: name, status: .running))
        refreshPill()

        // Safety timeout — auto-end session after 1 hour to prevent zombie pills
        sessionTimeoutTimers[sid]?.invalidate()
        sessionTimeoutTimers[sid] = Timer.scheduledTimer(withTimeInterval: sessionTimeoutInterval, repeats: false) { [weak self] _ in
            self?.endSession(sessionId: sid)
        }
    }

    func endSession(sessionId: String?) {
        if let sid = sessionId {
            activeSessions.removeAll { $0.id == sid }
            endSessionWorkItems.removeValue(forKey: sid)
            sessionTimeoutTimers[sid]?.invalidate()
            sessionTimeoutTimers.removeValue(forKey: sid)
        } else {
            // No ID — end all sessions
            activeSessions.removeAll()
            endSessionWorkItems.removeAll()
            sessionTimeoutTimers.values.forEach { $0.invalidate() }
            sessionTimeoutTimers.removeAll()
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

        windowController.showNotification(notification)

        // End session on completion (cancellable if a new session starts)
        if notification.type == .complete, let sid = notification.sessionId {
            endSessionWorkItems[sid]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.endSession(sessionId: sid)
            }
            endSessionWorkItems[sid] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5, execute: workItem)
        }
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

        // Auto-end test session after complete (cancellable)
        if type == .complete {
            let sid = "test-session"
            endSessionWorkItems[sid]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.endSession(sessionId: sid)
            }
            endSessionWorkItems[sid] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5, execute: workItem)
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
}
