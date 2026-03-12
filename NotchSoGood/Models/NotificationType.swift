import SwiftUI

enum NotificationType: String, CaseIterable {
    case complete
    case question
    case permission
    case general

    var mascotExpression: MascotExpression {
        switch self {
        case .complete: return .happy
        case .question: return .thinking
        case .permission: return .alert
        case .general: return .waving
        }
    }

    var accentColor: Color {
        switch self {
        case .complete: return Color(hex: "34D399")   // Emerald green
        case .question: return Color(hex: "60A5FA")   // Soft blue
        case .permission: return Color(hex: "FBBF24") // Amber
        case .general: return Color(hex: "A78BFA")    // Soft violet
        }
    }

    var sfSymbol: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .question: return "questionmark.circle.fill"
        case .permission: return "exclamationmark.lock.fill"
        case .general: return "hand.wave.fill"
        }
    }

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
