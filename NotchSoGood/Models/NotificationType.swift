import SwiftUI

enum NotificationType: String, CaseIterable {
    case complete
    case question
    case permission
    case general

    var defaultTitle: String {
        switch self {
        case .complete: return "Done"
        case .question: return "Question"
        case .permission: return "Permission"
        case .general: return "Claude"
        }
    }

    var soundName: String {
        switch self {
        case .complete: return "Glass"
        case .question: return "Blow"
        case .permission: return "Sosumi"
        case .general: return "Pop"
        }
    }
}
