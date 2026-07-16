import SwiftUI

/// The Dynamic Island / notch silhouette: concave fillets at the top corners
/// (so the shape flows out of the screen's top edge instead of meeting it at
/// a sharp 90°), convex rounded corners at the bottom.
///
/// The concave curves eat `topRadius` horizontally on each side, so the
/// straight side walls sit `topRadius` inside the frame.
struct NotchShape: Shape {
    var topRadius: CGFloat = 8
    var bottomRadius: CGFloat = 18

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, min(rect.width / 2 - t, rect.height / 2))

        var p = Path()
        // Top edge, full width — merges with the screen bezel
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Concave fillet down-in on the left
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )

        // Left wall
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))

        // Bottom-left convex corner
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )

        // Bottom edge
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))

        // Bottom-right convex corner
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )

        // Right wall
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))

        // Concave fillet up-out on the right
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )

        p.closeSubpath()
        return p
    }
}
