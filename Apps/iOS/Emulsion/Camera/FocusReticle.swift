import SwiftUI

struct FocusReticle: View {
    let point: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let point {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white, lineWidth: 1.5)
                    .frame(width: Layout.side, height: Layout.side)
                    .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                    .transition(reduceMotion ? .opacity : .scale(scale: Layout.appearingScale).combined(with: .opacity))
                    .accessibilityLabel("Focus point")
                    .accessibilityIdentifier(AccessibilityID.focusReticle)
            }
        }
        .animation(Layout.moveAnimation, value: point)
        .allowsHitTesting(false)
    }

    // Artistic: about the size of the system Camera's reticle, and how it appears and moves.
    private enum Layout {
        static let side: CGFloat = 76
        static let appearingScale = 1.4
        static let moveAnimation = Animation.snappy(duration: 0.25)
    }
}
