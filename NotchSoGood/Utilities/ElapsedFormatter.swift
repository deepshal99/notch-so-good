import Foundation

/// Elapsed-time strings for session timers.
///
/// Two forms, because the notch has two very different budgets:
///
/// * `precise` — `42s` / `7:31` / `1:08:02`. Used in the expanded rows and the
///   menu bar, where there's room for it.
/// * `compact` — same, except hours collapse to `1h08m`. The collapsed pill wing
///   is only 56pt wide; the precise form's seven glyphs overflowed it and got
///   clipped by the pill once a session passed an hour.
enum ElapsedFormatter {
    static func precise(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 60 {
            return String(format: "%02ds", total)
        }
        if total < 3600 {
            return "\(total / 60):\(String(format: "%02d", total % 60))"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", total % 60))"
    }

    /// Precise under an hour, then `1h08m` — seconds stop being interesting long
    /// before they stop fitting.
    static func compact(_ seconds: Int) -> String {
        let total = max(0, seconds)
        guard total >= 3600 else { return precise(total) }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours)h\(String(format: "%02d", minutes))m"
    }

    /// `precise`, but without the trailing "s" for sub-minute values — reads
    /// better in the wider menu bar rows.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 3600 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
