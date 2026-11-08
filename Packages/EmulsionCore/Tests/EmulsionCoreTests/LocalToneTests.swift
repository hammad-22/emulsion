import EmulsionFixtures
import XCTest
import simd

@testable import EmulsionCore

final class LocalToneTests: EmulsionTestCase {
    func testHighlightsAndShadowsDoNotHalo() throws {
        let step = Fixtures.image(width: 1200, height: 160, space: SceneFixtures.linear) { x, _ in
            SIMD3(repeating: x < 600 ? 0.03 : 2.5)
        }
        for (sh, hi) in [(0.8, 0.0), (0.0, 0.8)] {
            var a = Adjustments.neutral
            a.shadows = sh
            a.highlights = hi
            let row = Array(codes(try render(step, a))[pixel(x: 0, y: 80, width: 1200)..<pixel(x: 0, y: 81, width: 1200)]).map(luma)
            let dev = (0..<1200).filter { abs($0 - 600) > 4 }.map { abs(row[$0] - ($0 < 600 ? row[20] : row[1180])) }.max()!
            XCTAssertLessThanOrEqual(dev, 3)
        }
    }
}
