import Foundation

extension CharacterState {
    /// What a notification card's character expresses.
    init(notification: NotchNotification) {
        switch notification.type {
        case .permission, .question: self = .need
        case .complete: self = .done
        case .error: self = .error
        case .general:
            switch notification.title {
            case NotchNotification.limitsTitle, NotchNotification.radarTitle: self = .warn
            case NotchNotification.limitsOutTitle: self = .error
            case NotchNotification.limitsBackTitle, NotchNotification.updateTitle: self = .done
            case NotchNotification.nudgeTitle: self = .need
            default: self = .work
            }
        }
    }
}
