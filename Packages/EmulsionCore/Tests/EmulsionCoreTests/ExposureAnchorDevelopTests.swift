import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

struct ExposureAnchorDevelopTests {
    static var developer: Developer { RAWDevelopTests.developer }

    /// A "48 MP-like" and a "12 MP-like" profile file that render the same picture (docs).
    static let gainStops = 2.0
    static let twelveBaselineStops = 2.5
    static let fortyEightBaselineStops = twelveBaselineStops - gainStops
    static let scene = RAWDevelopChart.scene
    static let chart = PatchChart(scene.map { $0 * pow(2, -twelveBaselineStops) })
    /// Points every 0.05: longer spline segments bow (measured 0.032 stops at one segment).
    static let darkeningCurve: [SIMD2<Float>] =
        stride(from: Float(0), through: 0.9, by: 0.05).map { SIMD2($0, Float(darkeningCurveSlope) * $0) } + [SIMD2(1, 1)]
    static let darkeningCurveSlope = 0.7

    static let fortyEight = SyntheticDNG.Profile(gainTableGain: Float(pow(2, gainStops)))
    static let fortyEightDarkened = SyntheticDNG.Profile(gainTableGain: Float(pow(2, gainStops)), toneCurve: darkeningCurve)
    static let twelve = SyntheticDNG.Profile(gainTableGain: 1)

    static func develop(
        _ mosaic: SyntheticDNG.Mosaic, baselineStops: Double, profile: SyntheticDNG.Profile?, maxDimension: CGFloat? = nil,
        anchor: ExposureAnchor.Choice = .measured
    ) throws -> RAWDevelopSupport.Developed {
        try RAWDevelopSupport.develop(
            RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: baselineStops, profile: profile), chart: chart,
            maxDimension: maxDimension, anchor: anchor)
    }

    // Measured tolerances, about 2× the worst on macOS 27.2: docs/CONSTANTS.md, "Test tolerances".

    static let identityAnchorTolerance = 6e-4
    static let pairAnchorTolerance = 2e-6
    static let pairValueTolerance = 4e-4
    static let sceneTolerance = 0.003
    static let toneCurveShiftTolerance = 5e-4
    static let scalarTolerance = 2e-6
    static let scalarFloor = 1e-3
    static let concurrentDevelops = 8

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func filesThatRenderAlikeDevelopAlike(_ mosaic: SyntheticDNG.Mosaic) throws {
        let twelve = try Self.develop(mosaic, baselineStops: Self.twelveBaselineStops, profile: Self.twelve)
        let fortyEight = try Self.develop(mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let twelveAnchor = twelve.negative.exposureAnchorStops
        let fortyEightAnchor = fortyEight.negative.exposureAnchorStops
        #expect(abs(twelveAnchor) < Self.identityAnchorTolerance, "12 MP-like anchor \(twelveAnchor)")
        #expect(abs(fortyEightAnchor - twelveAnchor - Self.gainStops) < Self.pairAnchorTolerance, "48 MP-like anchor \(fortyEightAnchor)")
        let worstPair = RAWDevelopSupport.worstRelativeDifference(fortyEight.means, twelve.means, floor: 0.01)
        let worstScene = RAWDevelopSupport.worstRelativeDifference(fortyEight.means, Self.scene, floor: 1)
        #expect(worstPair < Self.pairValueTolerance, "worst relative difference between the files \(worstPair)")
        #expect(worstScene < Self.sceneTolerance, "worst difference from the scene \(worstScene)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func toneCurveShiftsTheAnchor(_ mosaic: SyntheticDNG.Mosaic) throws {
        let identity = try Self.develop(mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let darkened = try Self.develop(
            mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEightDarkened)
        let shift = darkened.negative.exposureAnchorStops - identity.negative.exposureAnchorStops
        #expect(abs(shift - log2(Self.darkeningCurveSlope)) < Self.toneCurveShiftTolerance, "shift \(shift)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func anchorIsAPureScalar(_ mosaic: SyntheticDNG.Mosaic) throws {
        let anchored = try Self.develop(mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let plain = try Self.develop(
            mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight, anchor: .none)
        #expect(plain.negative.exposureAnchorStops == 0)
        let gain = pow(2, anchored.negative.exposureAnchorStops)
        #expect(anchored.pixels.contains { $0.max() > 1 }, "no value above 1")
        #expect(anchored.pixels.contains { $0.min() < -Self.scalarFloor }, "no negative value")
        var worst = 0.0
        for (a, p) in zip(anchored.pixels, plain.pixels) {
            for channel in 0..<3 where abs(p[channel]) > Self.scalarFloor {
                worst = max(worst, abs(a[channel] / p[channel] / gain - 1))
            }
        }
        #expect(worst < Self.scalarTolerance, "worst relative error \(worst)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func previewAndFullDevelopShareTheAnchor(_ mosaic: SyntheticDNG.Mosaic) throws {
        let full = try Self.develop(mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let preview = try Self.develop(
            mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight,
            maxDimension: CGFloat(Self.chart.width / 2))
        #expect(preview.negative.size.width < full.negative.size.width)
        #expect(full.negative.exposureAnchorStops == preview.negative.exposureAnchorStops)
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func fullDevelopKeepsTheNativeSize(_ mosaic: SyntheticDNG.Mosaic) throws {
        let full = try Self.develop(mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        #expect(CGFloat(Self.chart.width) > ExposureAnchor.thumbnailLongEdge)
        #expect(full.negative.exposureAnchorStops != 0)
        #expect(full.negative.size == CGSize(width: Self.chart.width, height: Self.chart.height))
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func concurrentDevelopsAgree(_ mosaic: SyntheticDNG.Mosaic) async throws {
        let data = RAWDevelopChart.dng(
            mosaic, chart: Self.chart, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let results = try await withThrowingTaskGroup(of: (anchor: Double, pixels: [SIMD3<Double>]).self) { group in
            for _ in 0..<Self.concurrentDevelops {
                group.addTask {
                    let negative = try Self.developer.develop(data)
                    return (negative.exposureAnchorStops, Fixtures.linear(negative.image))
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        let first = try #require(results.first)
        #expect(first.anchor != 0)
        #expect(results.allSatisfy { $0.anchor == first.anchor && $0.pixels == first.pixels })
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func filesWithoutAProfileAreUnchanged(_ mosaic: SyntheticDNG.Mosaic) throws {
        for maxDimension in [nil, CGFloat(Self.chart.width / 2)] {
            let anchored = try Self.develop(mosaic, baselineStops: 1, profile: nil, maxDimension: maxDimension)
            let plain = try Self.develop(mosaic, baselineStops: 1, profile: nil, maxDimension: maxDimension, anchor: .none)
            #expect(anchored.negative.exposureAnchorStops == 0)
            #expect(anchored.pixels == plain.pixels)
        }
    }

    @Test func displayReferredPhotosHaveNoAnchor() throws {
        let data = try RAWDevelopTests.renderer.export(SceneFixtures.flat(0.18, width: 64, height: 64), format: .jpeg)
        #expect(try Self.developer.develop(data).exposureAnchorStops == 0)
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func givenAnchorReproducesTheMeasuredDevelop(_ mosaic: SyntheticDNG.Mosaic) throws {
        let data = RAWDevelopChart.dng(
            mosaic, chart: Self.chart, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        for maxDimension in [nil, CGFloat(Self.chart.width / 2)] {
            let measured = RAWDevelopSupport.Developed(chart: Self.chart, try Self.developer.develop(data, maxDimension: maxDimension))
            let anchor = measured.negative.exposureAnchorStops
            #expect(anchor != 0)
            let given = RAWDevelopSupport.Developed(
                chart: Self.chart, try Self.developer.develop(data, maxDimension: maxDimension, exposureAnchorStops: anchor))
            #expect(given.negative.exposureAnchorStops == anchor)
            if maxDimension == nil {
                #expect(given.pixels == measured.pixels)
            } else {
                let worst = zip(given.means, measured.means).map { abs($0 - $1).max() / max(1, abs($1).max()) }.max() ?? .nan
                #expect(worst < RAWDevelopTests.previewTolerance, "worst difference \(worst)")
            }
        }
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func givenAnchorIsAppliedAsGiven(_ mosaic: SyntheticDNG.Mosaic) throws {
        let data = RAWDevelopChart.dng(
            mosaic, chart: Self.chart, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let measured = RAWDevelopSupport.Developed(chart: Self.chart, try Self.developer.develop(data))
        let brighter = measured.negative.exposureAnchorStops + 1
        let given = RAWDevelopSupport.Developed(chart: Self.chart, try Self.developer.develop(data, exposureAnchorStops: brighter))
        #expect(given.negative.exposureAnchorStops == brighter)
        #expect(given.pixels == measured.pixels.map { $0 * 2 })
    }

    @Test func displayReferredPhotosIgnoreAGivenAnchor() throws {
        let data = try RAWDevelopTests.renderer.export(SceneFixtures.flat(0.18, width: 64, height: 64), format: .jpeg)
        let given = try Self.developer.develop(data, exposureAnchorStops: 2)
        #expect(given.exposureAnchorStops == 0)
        #expect(Fixtures.linear(given.image) == Fixtures.linear(try Self.developer.develop(data).image))
    }

    @Test func resizingAndMaterializingKeepTheAnchor() throws {
        let renderer = RAWDevelopTests.renderer
        let developed = try Self.develop(.linearRGB, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let anchor = developed.negative.exposureAnchorStops
        #expect(anchor != 0)
        #expect(renderer.resized(developed.negative, longestEdge: 64).exposureAnchorStops == anchor)
        #expect(try renderer.materialize(developed.negative).exposureAnchorStops == anchor)
    }
}
