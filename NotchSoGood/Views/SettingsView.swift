import SwiftUI
import Sparkle
import ServiceManagement

/// The Settings window: native tabs and grouped forms, like System Settings.
struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    let updater: SPUUpdater

    enum Tab: Hashable { case general, notifications, character }
    @State private var tab: Tab

    init(notificationManager: NotificationManager, updater: SPUUpdater, tab: Tab = .general) {
        self.notificationManager = notificationManager
        self.updater = updater
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(notificationManager: notificationManager, updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            NotificationSettings(notificationManager: notificationManager)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
                .tag(Tab.notifications)
            CharacterSettingsPane()
                .tabItem { Label("Character", systemImage: "face.smiling") }
                .tag(Tab.character)
        }
        .frame(width: 460)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject var notificationManager: NotificationManager
    let updater: SPUUpdater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hooksReinstalled = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        do {
                            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {}
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
            }

            Section {
                Toggle(isOn: $notificationManager.showSessionPill) {
                    Text("Show the session pill")
                    Text("Your character and the 5-hour usage ring, beside the notch while agents work.")
                }
                Toggle(isOn: $notificationManager.followActiveDisplay) {
                    Text("Follow the active display")
                    Text("Show on the screen your terminal is on, not only the built-in one.")
                }
            } header: {
                Text("Notch")
            }

            Section {
                LabeledContent {
                    Button(hooksReinstalled ? "Reinstalled" : "Reinstall") {
                        notificationManager.installHooks()
                        hooksReinstalled = true
                    }
                    .disabled(hooksReinstalled)
                } label: {
                    Text("Agent hooks")
                    Text("Connects Claude Code and Codex. Reinstall if cards stop appearing.")
                }
            } header: {
                Text("Agents")
            }

            Section {
                LabeledContent("Version \(version)") {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                }
                Toggle(isOn: $notificationManager.telemetryEnabled) {
                    Text("Share anonymous usage data")
                    Text("Counts only, like how many cards were shown. Never your code or prompts.")
                }
            } header: {
                Text("About")
            } footer: {
                HStack {
                    Spacer()
                    Link("Made by Deepak Maurya", destination: URL(string: "https://x.com/deepshal99")!)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

// MARK: - Notifications

struct NotificationSettings: View {
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        Form {
            Section {
                Toggle("A task finishes", isOn: $notificationManager.showOnComplete)
                Toggle("An agent asks you something", isOn: $notificationManager.showOnQuestion)
                Toggle(isOn: $notificationManager.showOnPermission) {
                    Text("A tool needs permission")
                    Text("Allow or deny from the notch. When off, requests are approved automatically.")
                }
            } header: {
                Text("Show a card when")
            }

            Section {
                Toggle(isOn: $notificationManager.nudgeEnabled) {
                    Text("Remind me when a session is waiting")
                    Text("One nudge if a session sits blocked on you.")
                }
                Toggle("Play sounds", isOn: $notificationManager.soundEnabled)
            }

            Section {
                LabeledContent("Allow") { KeyCaps(keys: ["⌃", "⌥", "A"]) }
                LabeledContent("Deny") { KeyCaps(keys: ["⌃", "⌥", "D"]) }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Answer the permission card on screen from any app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }
}

private struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

// MARK: - Character

struct CharacterSettingsPane: View {
    @ObservedObject private var settings = CharacterSettings.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    ForEach(CharacterKind.allCases) { kind in
                        characterChoice(kind)
                        if kind != CharacterKind.allCases.last { Spacer(minLength: 0) }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text(settings.kind.tagline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Finish") {
                    HStack(spacing: 7) {
                        ForEach(CharacterFinish.allCases) { finish in swatch(finish) }
                    }
                }
                LabeledContent {
                    Picker("Motion", selection: $settings.motion) {
                        ForEach(CharacterMotion.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    Text("Motion")
                    Text(settings.motion.note)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 318)
    }

    private func characterChoice(_ kind: CharacterKind) -> some View {
        let selected = settings.kind == kind
        return Button {
            withAnimation(Island.press) { settings.kind = kind }
        } label: {
            VStack(spacing: 7) {
                NotchTile(state: selected ? .need : .work, kind: kind, size: 76, radius: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: selected ? 2.5 : 0)
                            .padding(-3.5)
                    )
                Text(kind.displayName)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.displayName)
        .accessibilityHint(kind.tagline)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ finish: CharacterFinish) -> some View {
        let selected = settings.finish == finish
        return Button {
            settings.finish = finish
        } label: {
            Circle()
                .fill(finish.swatch)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .frame(width: 18, height: 18)
                .padding(2.5)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(finish.displayName)
        .accessibilityLabel(finish.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
