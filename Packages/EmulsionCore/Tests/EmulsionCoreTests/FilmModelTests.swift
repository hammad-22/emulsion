import EmulsionFixtures
import XCTest
import simd

@testable import EmulsionCore

final class FilmModelTests: EmulsionTestCase {
    func testCalibratedStockPrintsNeutralMidGray() {
        let m = FilmLook.stock
        let mid = m.render(SIMD3(repeating: 0.18))
        for c in 0..<3 { XCTAssertEqual(mid[c], m.middleGrayOut, accuracy: 1e-6) }
        // Monotone neutral response across 20 stops.
        var previous = -1.0
        for i in 0...400 {
            let y = m.render(SIMD3(repeating: 0.18 * pow(2, -10 + 20 * Double(i) / 400))).y
            XCTAssertGreaterThan(y, previous)
            previous = y
        }
    }

    /// The GPU kernel implements exactly the documented equations (Swift mirror).
    func testGPUMatchesSwiftFilmModel() throws {
        var colors = [SIMD3<Float>]()
        var seed: UInt32 = 11
        for _ in 0..<200 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let r = Float(seed >> 8 & 255) / 255
            let g = Float(seed >> 16 & 255) / 255
            let b = Float(seed >> 24) / 255
            // Mild chroma, wide exposure range: stays inside P3 so gamut mapping is inactive.
            let base = 0.5 + 0.5 * SIMD3(r, g, b)
            colors.append(base * Float(0.18 * pow(2, Double(r + g) * 6 - 6)))
        }
        let image = Fixtures.row(colors, space: SceneFixtures.linearP3)
        let gpu = codes(try render(image))
        for (i, c) in colors.enumerated() {
            let ref = FilmLook.stock.render(SIMD3(Double(c.x), Double(c.y), Double(c.z)))
            let refCodes = SIMD3((0..<3).map { Double(Fixtures.encode(Float(min(1, ref[$0])))) * 255 })
            for k in 0..<3 { XCTAssertEqual(gpu[i][k], refCodes[k], accuracy: 0.6, "color \(i) channel \(k)") }
        }
    }

    func testSkinStaysInItsHueFamilyAcrossExposure() {
        let skin = SIMD3<Double>(0.40, 0.20, 0.13)
        let hues = stride(from: -2.0, through: 1.0, by: 0.5).map { Fixtures.hue(p3ToLab(FilmLook.stock.render(skin * pow(2, $0)))) }
        XCTAssertLessThan(hues.max()! - hues.min()!, 16, "skin hue swings \(hues)")
        XCTAssertTrue(hues.allSatisfy { (30...70).contains($0) }, "skin leaves the warm family \(hues)")
    }

    func testBrightColorsFadeToWhiteGracefully() {
        for color: SIMD3<Double> in [[0.40, 0.20, 0.13], [0.12, 0.20, 0.45], [0.10, 0.25, 0.06], [0.55, 0.04, 0.03]] {
            let chroma = stride(from: 0.0, through: 5.0, by: 0.25).map {
                Fixtures.chroma(p3ToLab(FilmLook.stock.render(color * pow(2, $0))))
            }
            for (a, b) in zip(chroma, chroma.dropFirst()) where a > 0.02 {
                XCTAssertGreaterThan(b / a, 0.72, "abrupt desaturation for \(color): \(chroma)")
            }
            XCTAssertLessThan(chroma.last!, chroma.first!, "very bright colors should approach white")
        }
    }
}
