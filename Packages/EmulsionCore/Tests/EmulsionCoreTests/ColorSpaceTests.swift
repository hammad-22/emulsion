import XCTest
import simd

@testable import EmulsionCore

final class ColorSpaceTests: XCTestCase {
    /// Each curve's published 18% gray code value decodes to 0.18 (Swift mirror).
    let midGrayCodes: [(InputColorSpace, Double)] = [
        (.appleLog, 0.08550479 * log2(0.18 + 0.00964052) + 0.69336945),
        (.sLog3SGamut3Cine, 420.0 / 1023), (.arriLogC3, 0.391007), (.vLog, 0.423311),
        (.davinciIntermediate, 0.336043), (.acescct, 0.4135884), (.hlgRec2020, 0.38),
    ]

    func testPublishedMidGrayCodesDecodeTo18Percent() {
        for (space, code) in midGrayCodes {
            XCTAssertEqual(ColorMath.decode(code, curve: space.curve), 0.18, accuracy: 2e-4, space.title)
        }
        // LogC4: decode(encode(0.18)) from the published encoding.
        let (a, b, c) = (ColorMath.LogC4.a, ColorMath.LogC4.b, ColorMath.LogC4.c)
        let code4 = ((log2(a * 0.18 + 64) - 6) / 14) * b + c
        XCTAssertEqual(ColorMath.decode(code4, curve: 4), 0.18, accuracy: 1e-6)
    }

    func testGamutMatricesKeepNeutralsNeutralIncludingACESWhite() {
        for space in InputColorSpace.allCases {
            let gray = space.toWorking * SIMD3(repeating: 0.18)
            for c in 0..<3 { XCTAssertEqual(gray[c], 0.18, accuracy: 1e-4, space.title) }
        }
        // Rec.2020 pure red lies outside sRGB: negative green/blue in the working space.
        let red = InputColorSpace.hlgRec2020.toWorking * SIMD3(1, 0, 0)
        XCTAssertGreaterThan(red.x, 1.5)
        XCTAssertLessThan(red.y, 0)
    }
}
