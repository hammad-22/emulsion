import EmulsionFixtures
import XCTest

@testable import EmulsionCore

final class ToneTests: EmulsionTestCase {
    func testNeutralWedgeIsMonotoneNearNeutralAndRollsOffHighlights() throws {
        let (wedge, stops) = SceneFixtures.wedge()
        let rendered = try render(wedge)
        let out = codes(rendered)
        let labs = Fixtures.oklab(rendered)
        let mid = stops.firstIndex { $0 >= 0 }!
        // 18% gray → 0.17 display-linear ≈ 114 code (encoded).
        XCTAssertEqual(out[mid].y, Double(Fixtures.encode(Float(FilmLook.stock.middleGrayOut))) * 255, accuracy: 1.0)
        for i in 1..<out.count where stops[i] > -6 && stops[i] < 5.5 {
            XCTAssertGreaterThan(luma(out[i]) - luma(out[i - 1]), 0.05, "tone flattens at \(stops[i]) stops")
        }
        // The warm/cool split stays a tint, not a cast: |a,b| small on the gray scale, ~0 at mid-gray.
        XCTAssertLessThan(Fixtures.chroma(labs[mid]), 0.004)
        for (i, lab) in labs.enumerated() where stops[i] > -6 {
            XCTAssertLessThan(Fixtures.chroma(lab), 0.03, "gray tinted at \(stops[i])")
        }
        // Highlights roll toward white instead of clipping: +4 and +5.5 stops still differ.
        let at4 = stops.firstIndex { $0 >= 4 }!
        let at55 = stops.firstIndex { $0 >= 5.5 }!
        XCTAssertGreaterThan(luma(out[at55]) - luma(out[at4]), 2)
        XCTAssertLessThan(luma(out[at4]), 254)
    }

    func testExposureIsAMultiplierInSceneLight() throws {
        var a = Adjustments.neutral
        a.exposure = 1
        let pushed = codes(try render(SceneFixtures.flat(0.09, width: 8, height: 8), a))[0]
        let reference = codes(try render(SceneFixtures.flat(0.18, width: 8, height: 8)))[0]
        for c in 0..<3 { XCTAssertEqual(pushed[c], reference[c], accuracy: 0.05) }
    }

    func testPrinterLightsMoveColorInTheRightDirection() throws {
        let gray = SceneFixtures.flat(0.18, width: 8, height: 8)
        var a = Adjustments.neutral
        let base = codes(try render(gray, a))[0]
        a.warmth = 1
        let warm = codes(try render(gray, a))[0]
        a.warmth = 0
        a.tint = 1
        let magenta = codes(try render(gray, a))[0]
        XCTAssertGreaterThan(warm.x - warm.z, base.x - base.z + 10)
        XCTAssertLessThan(magenta.y, base.y - 3)
    }
}
