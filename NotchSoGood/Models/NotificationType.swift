import SwiftUI

enum NotificationType: String, CaseIterable {
    case complete
    case question
    case permission
    /// A turn that ended on an API error.
    case error
    case general

    var defaultTitle: String {
        switch self {
        case .complete: return "Done"
        case .question: return "Question"
        case .permission: return "Permission"
        case .error: return "Stopped"
        case .general: return "Claude"
        }
    }

    var soundName: String {
        switch self {
        case .complete: return "Glass"
        case .question: return "Blow"
        case .permission: return "Sosumi"
        case .error: return "Basso"
        case .general: return "Pop"
        }
    }
}
