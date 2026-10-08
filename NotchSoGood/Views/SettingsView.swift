import SwiftUI
import Sparkle
import ServiceManagement

/// Settings, in the island's language: an identity header with Done, icon
/// tabs, and grouped rows of icon, explanation and control.
struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    let updater: SPUUpdater?
    var onDone: () -> Void = {}

    enum Tab: String, CaseIterable, Identifiable {
        case general, alerts, character, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .alerts: return "Alerts"
            case .character: return "Character"
            case .about: return "About"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .alerts: return "bell.fill"
            case .character: return "face.smiling.inverse"
            case .about: return "info.circle.fill"
            }
        }
    }

    @State private var tab: Tab

    init(notificationManager: NotificationManager, updater: SPUUpdater?, tab: Tab = .general, onDone: @escaping () -> Void = {}) {
        self.notificationManager = notificationManager
        self.updater = updater
        self.onDone = onDone
        _tab = State(initialValue: tab)
    }

    static let width: CGFloat = 460
    static let height: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Panel.separator).frame(height: 1)
            tabBar
            Rectangle().fill(Panel.separator).frame(height: 1)
            // Scroll only when a pane outgrows the window; otherwise there's no
            // scroller track to draw at all.
            ViewThatFits(in: .vertical) {
                pane
                ScrollView(.vertical) { pane }.scrollIndicators(.never)
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.width)
        .background(Panel.background)
        .environment(\.colorScheme, .dark)
        .toggleStyle(PanelToggleStyle())
    }

    private var pane: some View {
        Group {
            switch tab {
            case .general: GeneralPane(notificationManager: notificationManager)
            case .alerts: AlertsPane(notificationManager: notificationManager)
            case .character: CharacterPane()
            case .about: AboutPane(notificationManager: notificationManager, updater: updater)
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            NotchTile(state: .work, size: 40, radius: 11, framing: .portrait, live: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notch So Good")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Panel.primary)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                    .font(Panel.subtitle)
                    .foregroundColor(Panel.secondary)
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(PanelButtonStyle(kind: .outline))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                let selected = item == tab
                Button {
                    withAnimation(Island.press) { tab = item }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(selected ? Panel.primary : Panel.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.08 : 0))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var notificationManager: NotificationManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hooksReinstalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelSection("In the notch") {
                PanelRow(icon: "capsule.fill", title: "Session pill",
                         subtitle: "Your character and the 5-hour ring beside the notch while agents work.") {
                    Toggle("", isOn: $notificationManager.showSessionPill).labelsHidden()
                }
                PanelDivider()
                PanelRow(icon: "display.2", title: "Follow the active display",
                         subtitle: "Show up on the screen your terminal is on.") {
                    Toggle("", isOn: $notificationManager.followActiveDisplay).labelsHidden()
                }
            }

            PanelSection("General") {
                PanelRow(icon: "play.circle.fill", title: "Open at login",
                         subtitle: "Start Notch So Good when you log in.") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { enable in
                            do {
                                if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {}
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    )).labelsHidden()
                }
                PanelDivider()
                PanelRow(icon: "link", title: "Agent hooks",
                         subtitle: "Connects Claude Code and Codex. Reinstall if cards stop appearing.") {
                    Button(hooksReinstalled ? "Reinstalled" : "Reinstall") {
                        notificationManager.installHooks()
                        hooksReinstalled = true
                    }
                    .buttonStyle(PanelButtonStyle(kind: hooksReinstalled ? .quiet : .outline))
                    .disabled(hooksReinstalled)
                }
            }
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

// MARK: - Alerts

private struct AlertsPane: View {
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelSection("Show a card when") {
                PanelRow(icon: "checkmark.circle.fill", title: "A task finishes") {
                    Toggle("", isOn: $notificationManager.showOnComplete).labelsHidden()
                }
                PanelDivider()
                PanelRow(icon: "questionmark.bubble.fill", title: "An agent asks you something") {
                    Toggle("", isOn: $notificationManager.showOnQuestion).labelsHidden()
                }
                PanelDivider()
                PanelRow(icon: "lock.shield.fill", title: "A tool needs permission",
                         subtitle: "Allow or deny from the notch. When off, Claude Code asks in the terminal as usual.") {
                    Toggle("", isOn: $notificationManager.showOnPermission).labelsHidden()
                }
                HStack(spacing: 10) {
                    KeyCaps(keys: ["⌃", "⌥", "A"])
                    Text("allows").font(Panel.subtitle).foregroundColor(Panel.secondary)
                    KeyCaps(keys: ["⌃", "⌥", "D"])
                    Text("denies, from any app").font(Panel.subtitle).foregroundColor(Panel.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Panel.rowPadding + Panel.iconColumn + 12)
                .padding(.trailing, Panel.rowPadding)
                .padding(.bottom, 13)
                .padding(.top, -4)
            }

            PanelSection("Reminders") {
                PanelRow(icon: "bell.badge.fill", title: "Nudge when a session waits",
                         subtitle: "One reminder if a session sits blocked on you.") {
                    Toggle("", isOn: $notificationManager.nudgeEnabled).labelsHidden()
                }
                PanelDivider()
                PanelRow(icon: "speaker.wave.2.fill", title: "Sound",
                         subtitle: "A short cue when an agent needs you or finishes.") {
                    Toggle("", isOn: $notificationManager.soundEnabled).labelsHidden()
                }
            }
        }
    }
}

private struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Panel.primary)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

// MARK: - Character

private struct CharacterPane: View {
    @ObservedObject private var settings = CharacterSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelSection {
                if CharacterKind.available.count > 1 {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 0) {
                            ForEach(CharacterKind.available) { kind in
                                choice(kind)
                                if kind != CharacterKind.available.last { Spacer(minLength: 0) }
                            }
                        }
                        Text(settings.kind.tagline)
                            .font(Panel.subtitle)
                            .foregroundColor(Panel.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Panel.rowPadding)
                } else {
                    // One character: a portrait, not a picker with one option.
                    HStack(spacing: 16) {
                        NotchTile(state: .need, size: 96, radius: 20)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(settings.kind.displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Panel.primary)
                            Text(settings.kind.tagline)
                                .font(Panel.subtitle)
                                .foregroundColor(Panel.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Panel.rowPadding)
                }
            }

            PanelSection("Look and feel") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Panel.icon)
                            .frame(width: Panel.iconColumn)
                        Text("Finish").font(Panel.title).foregroundColor(Panel.primary)
                        Spacer()
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                        ForEach(settings.kind.finishes) { finish in
                            swatch(finish)
                        }
                    }
                    .padding(.leading, Panel.iconColumn + 12)
                }
                .padding(.horizontal, Panel.rowPadding)
                .padding(.vertical, 13)
                PanelDivider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wind")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Panel.icon)
                            .frame(width: Panel.iconColumn)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Motion").font(Panel.title).foregroundColor(Panel.primary)
                            Text(settings.motion.note).font(Panel.subtitle).foregroundColor(Panel.secondary)
                        }
                    }
                    PanelSegmented(options: CharacterMotion.allCases.map { ($0, $0.displayName) }, selection: $settings.motion)
                        .fixedSize()
                        .padding(.leading, Panel.iconColumn + 12)
                }
                .padding(.horizontal, Panel.rowPadding)
                .padding(.vertical, 13)
            }
        }
    }

    private func choice(_ kind: CharacterKind) -> some View {
        let selected = settings.kind == kind
        return Button {
            withAnimation(Island.press) { settings.kind = kind }
        } label: {
            VStack(spacing: 8) {
                NotchTile(state: selected ? .need : .work, kind: kind, size: 80, radius: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
                            .padding(-3)
                    )
                Text(kind.displayName)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? Panel.primary : Panel.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel(kind.displayName)
        .accessibilityHint(kind.tagline)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ finish: CharacterFinish) -> some View {
        let selected = settings.finish == finish
        let name = finish.displayName(for: settings.kind)
        return Button {
            withAnimation(Island.press) { settings.finish = finish }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(finish.swatch(for: settings.kind))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .frame(width: 26, height: 26)
                    .padding(3)
                    .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                Text(name)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? Panel.primary : Panel.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var notificationManager: NotificationManager
    let updater: SPUUpdater?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelSection {
                PanelRow(icon: "arrow.triangle.2.circlepath", title: "Updates",
                         subtitle: "New versions install when you say so.") {
                    Button("Check now") { updater?.checkForUpdates() }
                        .buttonStyle(PanelButtonStyle(kind: .outline))
                        .disabled(updater == nil)
                }
                PanelDivider()
                PanelRow(icon: "chart.bar.fill", title: "Share anonymous usage data",
                         subtitle: "Counts only, like how many cards were shown. Never your code or prompts.") {
                    Toggle("", isOn: $notificationManager.telemetryEnabled).labelsHidden()
                }
            }

            HStack {
                Spacer()
                Link("Made by Deepak Maurya", destination: URL(string: "https://x.com/deepshal99")!)
                    .font(Panel.subtitle)
                    .foregroundColor(Panel.tertiary)
                Spacer()
            }
        }
    }
}
