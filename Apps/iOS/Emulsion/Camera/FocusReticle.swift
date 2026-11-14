import SwiftUI

struct FocusReticle: View {
    let point: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Artistic: about the size of the system Camera's reticle.
    private let side: CGFloat = 76
    private let corner: CGFloat = 4
    private let lineWidth: CGFloat = 1.5
    private let appearingScale = 1.4

    var body: some View {
        GeometryReader { proxy in
            if let point {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(.white, lineWidth: lineWidth)
                    .frame(width: side, height: side)
                    .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                    .transition(reduceMotion ? .opacity : .scale(scale: appearingScale).combined(with: .opacity))
                    .accessibilityLabel("Focus point")
                    .accessibilityIdentifier(AccessibilityID.focusReticle)
            }
        }
        .animation(.snappy(duration: 0.25), value: point)
        .allowsHitTesting(false)
    }
}
