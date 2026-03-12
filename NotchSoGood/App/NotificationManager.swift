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
            } else if activeSessionId != nil, let startTime = sessionStartTime {
                windowController.showSessionPill(sessionId: activeSessionId, startTime: startTime)
            }
        }
    }

    // Active session tracking
    @Published var activeSessionId: String?
    @Published var sessionStartTime: Date?

    private var endSessionWorkItem: DispatchWorkItem?
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

    func startSession(sessionId: String?) {
        guard showSessionPill else { return }

        // Cancel any pending end-session from a previous completion
        endSessionWorkItem?.cancel()
        endSessionWorkItem = nil

        activeSessionId = sessionId
        sessionStartTime = Date()
        windowController.showSessionPill(sessionId: sessionId, startTime: sessionStartTime!)
    }

    func endSession(sessionId: String?) {
        // End matching session, or any session if no ID given
        if sessionId == nil || sessionId == activeSessionId || activeSessionId == nil {
            activeSessionId = nil
            sessionStartTime = nil
            windowController.hideSessionPill()
        }
    }

    var hasActiveSession: Bool {
        activeSessionId != nil
    }

    // MARK: - Notifications

    func handleNotification(_ notification: NotchNotification) {
        // Auto-start session pill if not already showing
        if !hasActiveSession && showSessionPill {
            startSession(sessionId: notification.sessionId)
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
        if notification.type == .complete {
            endSessionWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.endSession(sessionId: notification.sessionId)
            }
            endSessionWorkItem = workItem
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
            startSession(sessionId: "test-session")
        }

        windowController.showNotification(notification)

        // Auto-end test session after complete (cancellable)
        if type == .complete {
            endSessionWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.endSession(sessionId: "test-session")
            }
            endSessionWorkItem = workItem
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
