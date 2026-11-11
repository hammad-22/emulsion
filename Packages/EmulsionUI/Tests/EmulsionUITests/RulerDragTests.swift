import Testing

@testable import EmulsionUI

struct RulerDragTests {
    @Test func verticalScrollingDoesNotChangeTheAdjustment() {
        var drag = RulerDrag()
        let value = drag.update(
            value: 0.5, translation: 3, verticalTranslation: 30,
            pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        #expect(value == 0.5)
        let later = drag.update(
            value: value, translation: 40, verticalTranslation: 35,
            pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        #expect(later == 0.5, "The original vertical intent remains locked")
        drag.end()
        let horizontal = drag.update(
            value: value, translation: -10, verticalTranslation: 2,
            pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        #expect(horizontal == 0.6)
    }

    @Test func fineMovementsAccumulateAcrossNeutralDetent() {
        var drag = RulerDrag()
        var value = 0.0
        for translation in 1...10 {
            value = drag.update(
                value: value, translation: Double(-translation), pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        }
        #expect(abs(value - 0.1) < 0.000001)
    }

    @Test func reversesImmediatelyAfterReachingBound() {
        var drag = RulerDrag()
        let high = drag.update(value: 0, translation: -300, pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        #expect(high == 1)
        let reversed = drag.update(value: high, translation: -290, pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        #expect(abs(reversed - 0.9) < 0.000001)
    }

    @Test func newGestureStartsFromLatestExternalValue() {
        var drag = RulerDrag()
        _ = drag.update(value: 0, translation: -50, pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        drag.end()
        let next = drag.update(value: -0.5, translation: 10, pointsPerUnit: 100, range: -1...1, neutral: 0, detent: 0.03)
        #expect(next == -0.6)
    }
}
