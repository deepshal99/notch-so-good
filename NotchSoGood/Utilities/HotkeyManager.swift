import Carbon
import AppKit

/// Global keyboard shortcuts for approving/denying the active permission prompt
/// without switching focus to the notch: ⌃⌥A approves, ⌃⌥D denies.
///
/// Uses the classic Carbon Event Manager (RegisterEventHotKey) — this is a
/// system-wide hotkey API that requires no Accessibility/Input Monitoring
/// permission, unlike CGEventTap-based approaches.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var approveHotKeyRef: EventHotKeyRef?
    private var denyHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private let approveHotKeyID = EventHotKeyID(signature: OSType(0x4E534741), id: 1) // "NSGA"
    private let denyHotKeyID = EventHotKeyID(signature: OSType(0x4E534744), id: 2)    // "NSGD"

    private init() {}

    /// Installs the handler. The keys themselves are only registered while a
    /// permission card is on screen (`setArmed`): holding ⌃⌥A / ⌃⌥D all day
    /// would take them from every other app.
    func start() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            HotkeyManager.shared.handleHotKeyEvent(event)
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    /// Registers ⌃⌥A / ⌃⌥D while true, releases them while false. If another
    /// app already owns a combination, registration fails quietly and the
    /// buttons still work.
    func setArmed(_ armed: Bool) {
        if armed {
            if approveHotKeyRef == nil {
                RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey), approveHotKeyID,
                                    GetApplicationEventTarget(), 0, &approveHotKeyRef)
            }
            if denyHotKeyRef == nil {
                RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), denyHotKeyID,
                                    GetApplicationEventTarget(), 0, &denyHotKeyRef)
            }
        } else {
            if let ref = approveHotKeyRef { UnregisterEventHotKey(ref); approveHotKeyRef = nil }
            if let ref = denyHotKeyRef { UnregisterEventHotKey(ref); denyHotKeyRef = nil }
        }
    }

    func stop() {
        setArmed(false)
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        switch hotKeyID.id {
        case approveHotKeyID.id:
            Task { @MainActor in
                let controller = NotificationManager.shared.windowController
                guard controller.hasActivePermission else { return }
                controller.approveActivePermission()
            }
        case denyHotKeyID.id:
            Task { @MainActor in
                let controller = NotificationManager.shared.windowController
                guard controller.hasActivePermission else { return }
                controller.denyActivePermission()
            }
        default:
            break
        }

        return noErr
    }
}
