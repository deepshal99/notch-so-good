import AVFoundation
import AppKit

class SoundManager {
    static let shared = SoundManager()
    var isEnabled = true

    private init() {}

    func play(for type: NotificationType) {
        guard isEnabled else { return }

        let soundName = type.soundName

        // Try system sounds first
        if let soundURL = findSystemSound(named: soundName) {
            NSSound(contentsOf: soundURL, byReference: true)?.play()
            return
        }

        // Fallback: use NSSound by name
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    private func findSystemSound(named name: String) -> URL? {
        let systemSoundsPath = "/System/Library/Sounds"
        let extensions = ["aiff", "caf", "wav"]

        for ext in extensions {
            let url = URL(fileURLWithPath: systemSoundsPath)
                .appendingPathComponent(name)
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
