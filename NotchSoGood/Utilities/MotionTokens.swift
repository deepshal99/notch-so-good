import SwiftUI

// MARK: - Motion tokens — the app's entire animation vocabulary lives here.

extension Animation {
    /// Quick UI responses — hover states, press feedback, small toggles
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 0.7)
    /// Standard transitions — expand/collapse, appear/disappear, layout changes
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// Playful character motion — bounces, wiggles, celebration
    static let bouncy = Animation.spring(response: 0.25, dampingFraction: 0.5)
    /// Row reveals inside expanding surfaces — brisker than .smooth
    static let brisk = Animation.spring(response: 0.25, dampingFraction: 0.8)
    /// Hover highlight fades
    static let hover = Animation.easeOut(duration: 0.12)
}
