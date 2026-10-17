import Carbon
import AppKit

/// Global keyboard shortcuts for the card on screen, so you can answer without
/// leaving what you're doing. All ⌃⌥:
///
///   A  allow (or approve the plan)        D  deny (or hand back)
///   S  allow for this session             1–6  pick an option
///   N  next waiting card                  O  open where it's running
///   R  type a reply or your own answer
///
/// Uses the classic Carbon Event Manager (RegisterEventHotKey), a system-wide
/// hotkey API that needs no Accessibility or Input Monitoring permission.
/// Keys are only held while a card that uses them is up: holding them all day
/// would take them from every other app. (Window managers like Rectangle use
/// ⌃⌥ with arrows and E, T, F, G, U, I, J, K, so those stay free.)
final class HotkeyManager {
    static let shared = HotkeyManager()

    enum Key: UInt32, CaseIterable {
        case allow = 1, deny, session, next, open, reply
        case option1 = 11, option2, option3, option4, option5, option6

        var keyCode: Int {
            switch self {
            case .allow: return kVK_ANSI_A
            case .deny: return kVK_ANSI_D
            case .session: return kVK_ANSI_S
            case .next: return kVK_ANSI_N
            case .open: return kVK_ANSI_O
            case .reply: return kVK_ANSI_R
            case .option1: return kVK_ANSI_1
            case .option2: return kVK_ANSI_2
            case .option3: return kVK_ANSI_3
            case .option4: return kVK_ANSI_4
            case .option5: return kVK_ANSI_5
            case .option6: return kVK_ANSI_6
            }
        }

        static func options(_ count: Int) -> [Key] {
            Array([Key.option1, .option2, .option3, .option4, .option5, .option6].prefix(count))
        }
    }

    private var registered: [Key: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let signature = OSType(0x4E534748) // "NSGH"

    private init() {}

    /// Installs the handler; `arm` decides which keys are live.
    func start() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            HotkeyManager.shared.handleHotKeyEvent(event)
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    /// Holds exactly these keys. If another app already owns a combination,
    /// registration fails quietly and the buttons still work.
    func arm(_ keys: Set<Key>) {
        for (key, ref) in registered where !keys.contains(key) {
            UnregisterEventHotKey(ref)
            registered[key] = nil
        }
        for key in keys where registered[key] == nil {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key.keyCode), UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: signature, id: key.rawValue),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered[key] = ref }
        }
    }

    func stop() {
        arm([])
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
        guard hotKeyID.signature == signature, let key = Key(rawValue: hotKeyID.id) else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            let controller = NotificationManager.shared.windowController
            switch key {
            case .allow: controller.approveActivePermission()
            case .deny: controller.denyActivePermission()
            case .session: controller.allowActiveForSession()
            case .next: controller.showNextWaitingCard()
            case .open: controller.openActiveCard()
            case .reply: controller.focusCardField()
            default: controller.pickOption(Int(key.rawValue - Key.option1.rawValue))
            }
        }
        return noErr
    }
}
