import CoreImage
import EmulsionFixtures
import XCTest

@testable import EmulsionCore

final class GrainTests: EmulsionTestCase {
    func testGrainIsZeroMeanMidtoneWeightedAndDeterministic() throws {
        var a = Adjustments.neutral
        // Realistic width: grain cells are ~1 px at 2400 px (sub-pixel grain is averaged away).
        let mid = SceneFixtures.flat(0.18, width: 2400, height: 300)
        let deep = SceneFixtures.flat(0.18 / 64, width: 2400, height: 300)
        let clean = codes(try render(mid, a)).map(luma)
        a.grain = 1
        a.seed = 3
        let grainy = codes(try render(mid, a)).map(luma)
        XCTAssertEqual(grainy.reduce(0, +) / Double(grainy.count), clean.reduce(0, +) / Double(clean.count), accuracy: 0.6)
        let sMid = sd(grainy)
        let sDeep = sd(codes(try render(deep, a)).map(luma))
        XCTAssertGreaterThan(sMid, 2, "grain visible in midtones")
        XCTAssertGreaterThan(sMid, 2 * sDeep, "less grain in deep shadows")
        XCTAssertEqual(codes(try render(mid, a)).map(luma), grainy, "same seed, same grain")
        a.grain = 0
        XCTAssertEqual(codes(try render(mid, a)).map(luma), clean)
    }

    /// Seeds one apart (3 vs 4) must give different grain; the hash used to drop the integer part.
    func testDifferentSeedsGiveDifferentGrain() throws {
        let mid = SceneFixtures.flat(0.18, width: 2400, height: 64)
        var a = Adjustments.neutral
        a.grain = 1
        func pattern(_ seed: Double) throws -> [Double] {
            a.seed = seed
            return codes(try render(mid, a)).map(luma)
        }
        let three = try pattern(3)
        let four = try pattern(4)
        let half = try pattern(3.5)
        XCTAssertNotEqual(three, four, "integer seeds collide")
        XCTAssertNotEqual(three, half)
        // Independent patterns: correlation near zero (identical would be 1).
        func corr(_ x: [Double], _ y: [Double]) -> Double {
            let mx = x.reduce(0, +) / Double(x.count)
            let my = y.reduce(0, +) / Double(y.count)
            let c = zip(x, y).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
            return c / (sd(x) * sd(y) * Double(x.count))
        }
        XCTAssertLessThan(abs(corr(three, four)), 0.05)
        var previous = try pattern(0)
        var worst = 0.0
        for n in 1...100 {
            let next = try pattern(Double(n))
            worst = max(worst, abs(corr(previous, next)))
            previous = next
        }
        XCTAssertLessThan(worst, 0.05, "neighbouring seeds 0…100 must be independent")
    }

    func testPreviewAndExportCarryMatchingGrain() throws {
        var a = Adjustments.neutral
        a.grain = 1
        a.seed = 9
        let export = SceneFixtures.flat(0.18, width: 4000, height: 3000)
        let negative = Negative(image: export, contract: .sceneReferred)
        let preview = renderer.resized(negative, longestEdge: 1600)
        let previewSD = sd(codes(try renderer.render(preview, a)).map(luma))
        let full = try renderer.render(negative, a)
        let down = full.lanczosScaled(by: 0.4)
            .cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let exportSD = sd(codes(down).map(luma))
        XCTAssertEqual(previewSD / exportSD, 1, accuracy: 0.35, "preview σ \(previewSD) vs downsampled export σ \(exportSD)")
    }
}
