import EmulsionFixtures
import XCTest

@testable import EmulsionCore

final class HalationTests: EmulsionTestCase {
    func testHalationOnlyAroundBrightHighlightsAndRedBiased() throws {
        var on = Adjustments.neutral
        on.halation = 1
        let flat = SceneFixtures.flat(1.0, width: 64, height: 64)
        XCTAssertEqual(
            codes(try render(flat, on))[pixel(x: 32, y: 32, width: 64)], codes(try render(flat))[pixel(x: 32, y: 32, width: 64)],
            "no halation below threshold")

        let point = SceneFixtures.highlightPoint()
        let with = codes(try render(point, on))
        let without = codes(try render(point))
        let ring = pixel(x: 214, y: 200, width: 400)  // ~8 px outside the source edge
        let delta = with[ring] - without[ring]
        XCTAssertGreaterThan(delta.x, 3, "visible glow")
        XCTAssertGreaterThan(delta.x, delta.y * 1.5)
        XCTAssertGreaterThan(delta.y, delta.z)
        let far = pixel(x: 20, y: 20, width: 400)
        XCTAssertEqual(with[far].x, without[far].x, accuracy: 0.5, "glow stays local")
    }

    func testHalationScalesWithImageSize() throws {
        var on = Adjustments.neutral
        on.halation = 1
        func glow(_ size: Int) throws -> Double {
            let point = SceneFixtures.highlightPoint(size: size)
            let w = codes(try render(point, on))
            let wo = codes(try render(point))
            let i = pixel(x: size / 2 + Int(0.04 * Double(size)), y: size / 2, width: size)
            return w[i].x - wo[i].x
        }
        XCTAssertEqual(try glow(400), try glow(800), accuracy: 1.5)
    }
}
