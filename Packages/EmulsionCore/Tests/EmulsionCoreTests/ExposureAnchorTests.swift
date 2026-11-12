import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// The exposure anchor's maths (MOV-134), on pixel arrays.
struct ExposureAnchorTests {
    /// Chromatic and neutral linear sRGB pixels from deep shadow to above 1, one with a negative channel.
    static let linear: [SIMD4<Float>] = [
        SIMD4(0.01, 0.01, 0.01, 1), SIMD4(0.045, 0.03, 0.02, 1), SIMD4(0.02, 0.06, 0.03, 1), SIMD4(0.05, 0.04, 0.09, 1),
        SIMD4(0.3, 0.2, 0.1, 1), SIMD4(0.8, -0.02, 0.05, 1), SIMD4(1.6, 1.4, 1.2, 1), SIMD4(0.25, 0.25, 0.25, 1),
    ]
    /// Pure arithmetic in Double from Float inputs.
    static let arithmeticTolerance = 1e-9

    static func scaled(_ pixels: [SIMD4<Float>], by gain: Float) -> [SIMD4<Float>] { pixels.map { $0 * gain } }

    @Test func uniformGainGivesItsStops() {
        let anchor = ExposureAnchor.stops(linear: Self.linear, profile: Self.scaled(Self.linear, by: 4))
        #expect(abs(anchor - 2) < Self.arithmeticTolerance, "anchor \(anchor)")
    }

    @Test func pixelsOutsideTheWindowDontCount() {
        // Rendered at mid-gray with a ×4 gain, against bright pixels (Y ≈ 2) with a ×0.5 gain.
        let inWindow = [SIMD4<Float>](repeating: SIMD4(0.045, 0.045, 0.045, 1), count: 10)
        let outside = [SIMD4<Float>](repeating: SIMD4(4, 4, 4, 1), count: 90)
        let anchor = ExposureAnchor.stops(
            linear: inWindow + outside, profile: Self.scaled(inWindow, by: 4) + Self.scaled(outside, by: 0.5))
        #expect(abs(anchor - 2) < Self.arithmeticTolerance, "anchor \(anchor)")
    }

    @Test func fewWindowPixelsFallBackToAllPixels() {
        // 1 pixel in 200 (0.5 %) in the window with ×4, the rest bright with ×2: mean of all ratios.
        let inWindow = [SIMD4<Float>(0.045, 0.045, 0.045, 1)]
        let outside = [SIMD4<Float>](repeating: SIMD4(2, 2, 2, 1), count: 199)
        let anchor = ExposureAnchor.stops(
            linear: inWindow + outside, profile: Self.scaled(inWindow, by: 4) + Self.scaled(outside, by: 2))
        let expected = (2.0 + 199 * 1) / 200
        #expect(abs(anchor - expected) < Self.arithmeticTolerance, "anchor \(anchor), expected \(expected)")
    }

    @Test func unusablePixelsGiveZero() {
        let black = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: 16)
        #expect(ExposureAnchor.stops(linear: black, profile: black) == 0)
        #expect(ExposureAnchor.stops(linear: [], profile: []) == 0)
        #expect(ExposureAnchor.stops(linear: Self.linear, profile: Array(Self.linear.dropLast())) == 0, "sizes differ")
    }

    @Test func nonFinitePixelsAreSkipped() {
        let nan = [SIMD4<Float>](repeating: SIMD4(.nan, 0.2, 0.2, 1), count: 4)
        let anchor = ExposureAnchor.stops(linear: Self.linear + nan, profile: Self.scaled(Self.linear, by: 4) + nan)
        #expect(abs(anchor - 2) < Self.arithmeticTolerance, "anchor \(anchor)")
    }

    @Test(arguments: [(Float(256), 5.0), (Float(1.0 / 16), -2.0)])
    func anchorIsClamped(gain: Float, expected: Double) {
        #expect(ExposureAnchor.stops(linear: Self.linear, profile: Self.scaled(Self.linear, by: gain)) == expected)
    }
}

/// The anchor through `Developer.develop` on synthetic DNGs whose profile carries a gain table
/// and a tone curve, which CIRAWFilter applies (macOS 27.2) as it does for real ProRAW.
struct ExposureAnchorDevelopTests {
    static var developer: Developer { RAWDevelopTests.developer }

    /// Same camera values in both files: a "48 MP-like" profile (BaselineExposure 0.5, gain ×4)
    /// and a "12 MP-like" one (BaselineExposure 2.5, gain ×1) render the same picture, so their
    /// anchored develops must agree; both put the chart's scene at its linear sRGB values.
    static let gainStops = 2.0
    static let twelveBaselineStops = 2.5
    static let fortyEightBaselineStops = twelveBaselineStops - gainStops
    static let scene = RAWDevelopChart.scene
    static let chart = PatchChart(scene.map { $0 * pow(2, -twelveBaselineStops) })
    /// TC(m) = 0.7 m up to 0.9, so over the whole window, chromatic patches included. Points every
    /// 0.05: the profile tone curve is interpolated with a cubic spline, which longer segments
    /// bow (one segment to 0.9 moved the anchor 0.032 stops, points every 0.1 by 0.008).
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

    // MARK: Tolerances (about 2× the worst value measured on macOS 27.2, Bayer and linear files)

    /// Measured worst 3.0e-4 stops (12 MP-like, identity curve).
    static let identityAnchorTolerance = 6e-4
    /// Measured worst 8.1e-7 stops: 48 MP-like anchor − 12 MP-like anchor − 2.
    static let pairAnchorTolerance = 2e-6
    /// Measured worst 2.1e-4 (relative, any channel, any patch) between the two anchored develops.
    static let pairValueTolerance = 4e-4
    /// Measured worst 0.0014 (relative to the larger of 1 and the value, any channel) against the scene.
    static let sceneTolerance = 0.003
    /// Measured worst 2.2e-4 stops: tone-curve anchor shift against log2(0.7).
    static let toneCurveShiftTolerance = 5e-4
    /// Measured worst 6.4e-7 (relative) per pixel and channel: anchored ÷ un-anchored against 2^anchor.
    static let scalarTolerance = 2e-6
    /// Pixels this close to zero have no meaningful ratio.
    static let scalarFloor = 1e-3

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

    /// The anchor is one multiply: every pixel and channel (chromatic, above 1, negative) scales
    /// by 2^anchor, so ratios between pixels don't change.
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

    /// The anchor's thumbnails must not leave the negative at thumbnail size.
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func fullDevelopKeepsTheNativeSize(_ mosaic: SyntheticDNG.Mosaic) throws {
        let full = try Self.develop(mosaic, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        #expect(CGFloat(Self.chart.width) > ExposureAnchor.thumbnailLongEdge)
        #expect(full.negative.exposureAnchorStops != 0)
        #expect(full.negative.size == CGSize(width: Self.chart.width, height: Self.chart.height))
    }

    /// Previews and exports of one file can develop at the same time through the renderer's
    /// shared context: they must get the same anchor and pixels as each other.
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func concurrentDevelopsAgree(_ mosaic: SyntheticDNG.Mosaic) async throws {
        let data = RAWDevelopChart.dng(
            mosaic, chart: Self.chart, baselineStops: Self.fortyEightBaselineStops, profile: Self.fortyEight)
        let results = try await withThrowingTaskGroup(of: (anchor: Double, pixels: [SIMD3<Double>]).self) { group in
            for _ in 0..<8 {
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

    /// A develop given the anchor an earlier develop reported (`RenderService` reuses it per file)
    /// skips the thumbnails: full size it matches the measuring develop exactly; a preview may
    /// then decode in draft mode, which the measuring develop doesn't (measured worst 0 on these
    /// files, macOS 27.2), so it gets the draft preview's tolerance.
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

    /// A given anchor is applied as given, without measuring: one stop more than the measured
    /// anchor develops exactly twice as bright.
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
