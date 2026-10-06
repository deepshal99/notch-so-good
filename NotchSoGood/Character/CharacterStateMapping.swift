import Foundation

extension CharacterState {
    /// What a notification card's character expresses.
    init(notification: NotchNotification) {
        switch notification.type {
        case .permission, .question: self = .need
        case .complete: self = .done
        case .general:
            switch notification.title {
            case NotchNotification.limitsTitle: self = .warn
            case NotchNotification.nudgeTitle: self = .need
            default: self = .work
            }
        }
    }
}
