import AppKit
import Sparkle

/// Updates without a trip to a website: Sparkle checks every hour, downloads a
/// new version quietly, and this surfaces it as "Update ready · Restart" in the
/// menu, plus one card in the notch when nothing else is going on.
/// Restarting installs it; quitting the app installs it too.
@MainActor
final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    /// The downloaded version waiting for a restart ("4.7.1"), if any.
    @Published private(set) var readyVersion: String?
    /// A version found by a scheduled check that couldn't download on its own
    /// (it needs a click): offered in the menu instead of a window popping up.
    @Published private(set) var availableVersion: String?
    weak var updater: SPUUpdater?
    private var installNow: (() -> Void)?
    private var announced = false

    /// Restart into the downloaded version.
    func installAndRestart() {
        guard let installNow else { return }
        Telemetry.shared.trackEvent("update_restart")
        installNow()
    }

    /// Show the notch card once, and only when no agent is busy: an update is
    /// never more important than your work. Called again as sessions end.
    func announceIfQuiet() {
        guard let version = readyVersion, !announced else { return }
        let manager = NotificationManager.shared
        guard !manager.hasActiveSession, PermissionServer.shared.pendingCount == 0 else { return }
        announced = true
        manager.handleNotification(NotchNotification(
            type: .general,
            message: "Notch So Good \(version) is downloaded. Click to restart into it. If macOS asks, let it update apps (once).",
            title: NotchNotification.updateTitle
        ))
    }

    /// Show Sparkle's own window for an update that needs a click.
    func showAvailableUpdate() {
        availableVersion = nil
        updater?.checkForUpdates()
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // A background check never pops a window over your work.
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.availableVersion = version }
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        Task { @MainActor in
            self.readyVersion = version
            self.installNow = immediateInstallHandler
            self.announceIfQuiet()
        }
        return true
    }
}
