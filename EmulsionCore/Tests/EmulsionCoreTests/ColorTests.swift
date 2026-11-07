import EmulsionFixtures
import XCTest
import simd

@testable import EmulsionCore

final class ColorTests: EmulsionTestCase {
    func testSaturatedColorsStayInP3AndKeepHueFamily() throws {
        let cell = 64
        let image = SceneFixtures.patches(cell: cell)
        let width = cell * SceneFixtures.patchesP3.count
        let input = Fixtures.oklab(image)
        let rendered = try render(image)
        let out = codes(rendered)
        let outLab = Fixtures.oklab(rendered)
        for i in 0..<SceneFixtures.patchesP3.count {
            let p = pixel(x: i * cell + cell / 2, y: cell / 2, width: width)
            XCTAssertTrue((0...255.01).contains(out[p].x) && (0...255.01).contains(out[p].y) && (0...255.01).contains(out[p].z))
            if Fixtures.chroma(input[p]) > 0.03 {
                XCTAssertLessThan(Fixtures.hueDifference(input[p], outLab[p]), 12, "patch \(i) hue skew")
            }
        }
    }

    func testNeonGradientDoesNotCollapse() throws {
        // Scene-linear magenta→red neon ramp, pushed into the highlight shoulder. Every tone
        // scale compresses highlights, so judge color steps against the *neutral* tone scale's
        // own compression at the same brightness: colors must not merge faster than gray does.
        let values = (0..<64).map { x -> SIMD3<Float> in
            let t = Float(x) / 63
            return SIMD3(2.0, 0.05, 1.6 * (1 - t))
        }
        let ramp = Fixtures.row(values, space: SceneFixtures.linearP3)
        let grays = Fixtures.row(values.map { SIMD3(repeating: Float(luma(SIMD3<Double>($0)))) }, space: SceneFixtures.linearP3)
        let input = Fixtures.oklab(ramp)
        let output = Fixtures.oklab(try render(ramp))
        let gIn = Fixtures.oklab(grays)
        let gOut = Fixtures.oklab(try render(grays))
        for i in 1..<64 {
            let color = Fixtures.deltaE(output[i], output[i - 1]) / max(1e-9, Fixtures.deltaE(input[i], input[i - 1]))
            let neutral = Fixtures.deltaE(gOut[i], gOut[i - 1]) / max(1e-9, Fixtures.deltaE(gIn[i], gIn[i - 1]))
            XCTAssertGreaterThan(color, 0.5 * neutral, "step \(i): color \(color) vs neutral \(neutral)")
        }
    }
}
