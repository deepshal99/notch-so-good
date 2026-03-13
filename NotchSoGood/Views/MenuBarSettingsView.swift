import SwiftUI
import Sparkle

struct MenuBarSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @State private var hoveredPreview: NotificationType?
    @State private var showUpdateInfo = false
    let updater: SPUUpdater

    private let bg = Color(hex: "1A1A1A")
    private let cardBg = Color.white.opacity(0.05)
    private let subtleText = Color.white.opacity(0.4)
    private let bodyText = Color.white.opacity(0.85)

    var body: some View {
        VStack(spacing: 0) {
            // === HEADER with Chawd ===
            header
                .padding(.top, 16)
                .padding(.bottom, 12)

            // === NOTIFICATION TOGGLES ===
            sectionLabel("NOTIFICATIONS")
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 1) {
                notifToggle(
                    icon: "checkmark.circle.fill",
                    label: "Task Complete",
                    color: NotificationType.complete.accentColor,
                    isOn: $notificationManager.showOnComplete
                )
                notifToggle(
                    icon: "questionmark.circle.fill",
                    label: "Questions",
                    color: NotificationType.question.accentColor,
                    isOn: $notificationManager.showOnQuestion
                )
                notifToggle(
                    icon: "exclamationmark.lock.fill",
                    label: "Permissions",
                    color: NotificationType.permission.accentColor,
                    isOn: $notificationManager.showOnPermission
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)

            Spacer().frame(height: 14)

            // === DISPLAY SETTINGS ===
            sectionLabel("DISPLAY")
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 1) {
                settingToggle(
                    icon: "waveform",
                    label: "Sound Effects",
                    isOn: $notificationManager.soundEnabled
                )
                settingToggle(
                    icon: "capsule.fill",
                    label: "Session Pill",
                    isOn: $notificationManager.showSessionPill
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)

            Spacer().frame(height: 14)

            // === PREVIEW ===
            sectionLabel("PREVIEW")
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                previewButton(type: .complete)
                previewButton(type: .question)
                previewButton(type: .permission)
                previewButton(type: .general)
            }
            .padding(.horizontal, 12)

            Spacer().frame(height: 10)

            // === FOOTER ===
            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.horizontal, 12)

            Button {
                showUpdateInfo.toggle()
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(subtleText)
                    Text("Update")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(bodyText)
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(subtleText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())

            if showUpdateInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To update, run in Terminal:")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(subtleText)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("cd ~/notch-so-good && git pull && bash install.sh", forType: .string)
                    } label: {
                        HStack(spacing: 6) {
                            Text("cd ~/notch-so-good && git pull && bash install.sh")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(subtleText)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(subtleText)
                    Text("Quit Notch So Good")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(bodyText)
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(subtleText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .keyboardShortcut("q")
            .padding(.bottom, 4)
        }
        .frame(width: 260)
        .background(bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            MascotView(expression: .waving)
                .frame(width: 44, height: 38)

            VStack(spacing: 2) {
                Text("Notch So Good")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Dynamic Island for Claude Code")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(subtleText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(subtleText)
            .tracking(0.8)
    }

    // MARK: - Notification Toggle Row

    private func notifToggle(
        icon: String,
        label: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(bodyText)

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(cardBg)
    }

    // MARK: - Setting Toggle Row

    private func settingToggle(
        icon: String,
        label: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 20)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(bodyText)

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(cardBg)
    }

    // MARK: - Preview Buttons

    private func previewButton(type: NotificationType) -> some View {
        let isHovered = hoveredPreview == type

        return Button {
            notificationManager.showTestNotification(type: type)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(type.accentColor.opacity(isHovered ? 0.2 : 0.1))
                        .frame(width: 36, height: 36)

                    Image(systemName: type.sfSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(type.accentColor)
                }

                Text(type.defaultTitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(isHovered ? type.accentColor : subtleText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBg.opacity(isHovered ? 1.5 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredPreview = h ? type : nil
            }
        }
    }
}

// MARK: - Hover Button Style

private struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isHovered ? 0.06 : 0))
                    .padding(.horizontal, 4)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { h in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
            }
    }
}
