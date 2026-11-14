import CoreGraphics

/// How an iOS drag on a ruler's scale is handled; see Packages/EmulsionUI/AGENTS.md.
enum ScrubStart: Equatable {
    /// At least as horizontal as vertical (a still start included): scrub the value.
    case scrub
    /// Vertical with nothing behind that can scroll: take the touch so nothing behind it moves.
    case claim
    /// Vertical over a scroll view that can scroll: leave the drag to it.
    case yield

    init(velocity: CGPoint, canScrollVertically: Bool) {
        if abs(velocity.x) >= abs(velocity.y) {
            self = .scrub
        } else {
            self = canScrollVertically ? .yield : .claim
        }
    }

    func reported(_ translation: CGPoint) -> CGSize {
        CGSize(width: translation.x, height: self == .scrub ? 0 : translation.y)
    }
}
