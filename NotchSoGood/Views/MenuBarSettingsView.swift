import SwiftUI

struct MenuBarSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Text("🦀")
                    .font(.system(size: 16))
                Text("Notch So Good")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            Divider().opacity(0.3)

            // Toggles
            Group {
                Toggle("Sound Effects", isOn: $notificationManager.soundEnabled)
                Toggle("Session Pill", isOn: $notificationManager.showSessionPill)
                Toggle("Task Complete", isOn: $notificationManager.showOnComplete)
                Toggle("Questions", isOn: $notificationManager.showOnQuestion)
                Toggle("Permissions", isOn: $notificationManager.showOnPermission)
            }
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider().opacity(0.3)

            // Test buttons
            Text("PREVIEW")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .tracking(0.5)

            HStack(spacing: 4) {
                testButton("checkmark.circle", color: .green, type: .complete)
                testButton("questionmark.bubble", color: .blue, type: .question)
                testButton("lock.shield", color: .orange, type: .permission)
                testButton("hand.wave", color: .purple, type: .general)
            }

            Divider().opacity(0.3)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 210)
    }

    private func testButton(_ icon: String, color: Color, type: NotificationType) -> some View {
        Button {
            notificationManager.showTestNotification(type: type)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .frame(width: 36, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}
