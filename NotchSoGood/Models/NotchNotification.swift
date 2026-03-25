import Foundation

struct NotchNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let message: String
    let title: String?
    let sessionId: String?
    let sourceBundleId: String?
    let timestamp = Date()

    // Permission approval fields (non-nil when this is an interactive permission request)
    let permissionRequestId: String?
    let toolName: String?

    init(
        type: NotificationType,
        message: String,
        title: String? = nil,
        sessionId: String? = nil,
        sourceBundleId: String? = nil,
        permissionRequestId: String? = nil,
        toolName: String? = nil
    ) {
        self.type = type
        self.message = message
        self.title = title
        self.sessionId = sessionId
        self.sourceBundleId = sourceBundleId
        self.permissionRequestId = permissionRequestId
        self.toolName = toolName
    }

    var displayTitle: String {
        title ?? type.defaultTitle
    }

    var isInteractivePermission: Bool {
        permissionRequestId != nil
    }
}
