import SwiftUI

/// A square where the user tapped to focus, fading after a moment. It appears without
/// zooming when Reduce Motion is on.
struct FocusReticle: View {
    let point: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Artistic: about the size of the system Camera's reticle.
    private let side: CGFloat = 76
    private let corner: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            if let point {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(.white, lineWidth: 1.5)
                    .frame(width: side, height: side)
                    .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
                    .accessibilityLabel("Focus point")
                    .accessibilityIdentifier("focus-reticle")
            }
        }
        .animation(.snappy(duration: 0.25), value: point)
        .allowsHitTesting(false)
    }
}
