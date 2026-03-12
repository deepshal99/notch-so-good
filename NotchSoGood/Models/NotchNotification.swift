import Foundation

struct NotchNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let message: String
    let title: String?
    let sessionId: String?
    let sourceBundleId: String?
    let timestamp = Date()

    var displayTitle: String {
        title ?? type.defaultTitle
    }
}
