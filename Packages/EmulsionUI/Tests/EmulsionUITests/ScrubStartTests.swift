import CoreGraphics
import Testing

@testable import EmulsionUI

struct ScrubStartTests {
    @Test func aStillStartScrubs() {
        #expect(ScrubStart(velocity: .zero, canScrollVertically: true) == .scrub)
        #expect(ScrubStart(velocity: CGPoint(x: 40, y: 40), canScrollVertically: true) == .scrub)
    }

    @Test func verticalDragsGoToAScrollViewOnlyWhenItCanScroll() {
        let downward = CGPoint(x: 5, y: 300)
        #expect(ScrubStart(velocity: downward, canScrollVertically: true) == .yield)
        #expect(ScrubStart(velocity: downward, canScrollVertically: false) == .claim)
    }

    @Test func anAcceptedScrubIsNeverLockedVerticalByTheRuler() {
        // The pan accepted a mostly horizontal start; the finger then drifts down.
        let start = ScrubStart(velocity: CGPoint(x: 100, y: 20), canScrollVertically: false)
        var drag = RulerDrag()
        let first = start.reported(CGPoint(x: -2, y: 12))
        let value = drag.update(
            value: 0, translation: first.width, verticalTranslation: first.height,
            pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0)
        #expect(value == 0.02)
    }

    @Test func aClaimedVerticalDragChangesNothing() {
        let start = ScrubStart(velocity: CGPoint(x: 0, y: 300), canScrollVertically: false)
        var drag = RulerDrag()
        let first = start.reported(CGPoint(x: 3, y: 40))
        let value = drag.update(
            value: 0.5, translation: first.width, verticalTranslation: first.height,
            pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0)
        #expect(value == 0.5)
    }
}
