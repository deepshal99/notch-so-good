import SwiftUI

enum SessionStatus: String {
    case running
    case needsInput
    case needsPermission
    case completed

    var dotColor: Color {
        switch self {
        case .running:         return Color(hex: "4ADE80") // green
        case .needsInput:      return Color(hex: "60A5FA") // blue
        case .needsPermission: return Color(hex: "FBBF24") // amber
        case .completed:       return Color(hex: "4ADE80").opacity(0.5)
        }
    }

    var shouldPulse: Bool {
        switch self {
        case .running: return true
        case .needsInput, .needsPermission: return true
        case .completed: return false
        }
    }

    var label: String? {
        switch self {
        case .running: return nil
        case .needsInput: return "Needs input"
        case .needsPermission: return "Permission"
        case .completed: return "Done"
        }
    }
}
