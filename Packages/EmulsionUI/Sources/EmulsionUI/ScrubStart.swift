import CoreGraphics

/// How a drag that starts on a ruler's scale is handled on iOS, decided once when it starts.
enum ScrubStart: Equatable {
    /// At least as horizontal as vertical (a still start included): scrub the value.
    case scrub
    /// Vertical with nothing behind that can scroll: take the touch so nothing behind it
    /// moves (the editor's dismiss gesture, say); `RulerDrag` then ignores it.
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

    /// The translation `RulerDrag` sees: a scrub's direction is already decided, so its
    /// vertical travel is dropped; a claimed drag keeps it so `RulerDrag` locks it out.
    func reported(_ translation: CGPoint) -> CGSize {
        CGSize(width: translation.x, height: self == .scrub ? 0 : translation.y)
    }
}
