import CoreGraphics

/// How an iOS drag on a ruler's scale is handled; see Packages/EmulsionUI/AGENTS.md.
enum ScrubStart: Equatable {
    case scrub
    case claim
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
