import CoreImage
import EmulsionFixtures
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import simd

@testable import EmulsionCore

/// RAW develop on synthetic DNGs (MOV-79): linear scene light with highlight headroom, neutral
/// clipped highlights and no gamut mapping, for Bayer and linear (ProRAW-container) files.
struct RAWDevelopTests {
    static var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    static var developer: Developer { renderer.developer }
    static let chart = RAWDevelopChart.chart()
    static let cameraValues = RAWDevelopChart.cameraValues(chart.patches)

    static func develop(
        _ mosaic: SyntheticDNG.Mosaic, baselineStops: Double, maxDimension: CGFloat? = nil
    ) throws -> RAWDevelopSupport.Developed {
        try RAWDevelopSupport.develop(
            RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: baselineStops), chart: chart, maxDimension: maxDimension)
    }

    /// Developed linear sRGB of a camera value, from the fixture's own maths: the sensor clips to
    /// 0…1, the as-shot neutral maps to D65 white (the matrix's calibration illuminant), and
    /// BaselineExposure scales the result.
    static func expected(camera: SIMD3<Double>, baselineStops: Double) -> SIMD3<Double> {
        let sensor = simd_clamp(camera, SIMD3(repeating: 0), SIMD3(repeating: 1))
        return SyntheticDNG.xyzFromLinearSRGB.inverse * RAWDevelopChart.camera.inverse * sensor * pow(2, baselineStops)
    }

    /// Neutral patches whose camera channels all stay below 95 % of sensor white.
    static let unclippedNeutrals = RAWDevelopChart.neutralIndices.filter { cameraValues[$0].max() < 0.95 }
    /// Neutral patches with at least one channel at or above sensor white.
    static let clippedNeutrals = RAWDevelopChart.neutralIndices.filter { cameraValues[$0].max() >= 1 }

    // Tolerances are about 2× the worst value measured on macOS 27.2, Bayer and linear files.

    /// Measured worst 0.0024 (relative, any channel, BaselineExposure 0 and 2; headroom patch 0.0016).
    static let linearTolerance = 0.005
    /// Measured worst 0.0021 (max |R/G − 1|, |B/G − 1|) on unclipped neutrals.
    static let neutralTolerance = 0.0045
    /// Measured worst 0.0222 (+3 stop patch: green clipped, blue rebuilt 2 % high).
    static let clippedNeutralTolerance = 0.045
    /// Measured worst 0.0016 (absolute, any channel, chromatic patches, linear sRGB).
    static let chromaticTolerance = 0.0035
    /// Measured worst 0.0012 (relative to max(1, value), draft half size vs full).
    static let previewTolerance = 0.0025

    /// The opposite case (a ProRAW file that ImageIO types as TIFF when read from memory must
    /// still develop as RAW) needs real files: `RAWDevelopRealFileTests`.
    @Test func plainTIFFIsNotRAW() throws {
        let image = try Self.renderer.cgImage(SceneFixtures.flat(0.18, width: 64, height: 64))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(!Developer.isRAW(data as Data))
        #expect(try Self.developer.develop(data as Data).contract == .displayReferred)
    }

    /// Exposure that puts the brightest unclipped neutral (camera 0.72) at 5.76, above 4.0.
    static let headroomBaselineStops = 3.0

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func developedHighlightsKeepHeadroom(_ mosaic: SyntheticDNG.Mosaic) throws {
        let developed = try Self.develop(mosaic, baselineStops: Self.headroomBaselineStops)
        let brightest = try #require(Self.unclippedNeutrals.last)
        let expected = Self.expected(camera: Self.cameraValues[brightest], baselineStops: Self.headroomBaselineStops)
        #expect(expected.y > RAWDevelopSupport.headroomFloor)
        let measured = developed.means[brightest]
        #expect(
            abs(measured.y / expected.y - 1) < Self.linearTolerance,
            "brightest unclipped neutral: expected \(expected.y), measured \(measured.y)")
        #expect(developed.maxValue > RAWDevelopSupport.headroomFloor, "max over the image \(developed.maxValue)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases, [0.0, 2.0])
    func developedNeutralsAreLinear(_ mosaic: SyntheticDNG.Mosaic, baselineStops: Double) throws {
        let developed = try Self.develop(mosaic, baselineStops: baselineStops)
        var worstLinear = 0.0
        var worstNeutral = 0.0
        for index in Self.unclippedNeutrals {
            let expected = Self.expected(camera: Self.cameraValues[index], baselineStops: baselineStops)
            let measured = developed.means[index]
            worstLinear = max(worstLinear, (abs(measured / expected - 1)).max())
            worstNeutral = max(worstNeutral, RAWDevelopSupport.neutralError(measured))
        }
        #expect(worstLinear < Self.linearTolerance, "worst relative error \(worstLinear)")
        #expect(worstNeutral < Self.neutralTolerance, "worst neutral error \(worstNeutral)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func clippedHighlightsStayNeutral(_ mosaic: SyntheticDNG.Mosaic) throws {
        let developed = try Self.develop(mosaic, baselineStops: 2)
        let lastUnclipped = try #require(Self.unclippedNeutrals.last)
        #expect(!Self.clippedNeutrals.isEmpty)
        for index in Self.clippedNeutrals {
            let measured = developed.means[index]
            #expect(RAWDevelopSupport.neutralError(measured) < Self.clippedNeutralTolerance, "patch \(index): \(measured)")
            #expect(measured.y >= developed.means[lastUnclipped].y, "patch \(index) darker than the last unclipped patch")
        }
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func saturatedColoursAreNotGamutMapped(_ mosaic: SyntheticDNG.Mosaic) throws {
        let developed = try Self.develop(mosaic, baselineStops: 0)
        var worst = 0.0
        for index in RAWDevelopChart.chromaticIndices {
            let expected = Self.expected(camera: Self.cameraValues[index], baselineStops: 0)
            worst = max(worst, abs(developed.means[index] - expected).max())
        }
        #expect(worst < Self.chromaticTolerance, "worst absolute error \(worst)")
        for index in RAWDevelopChart.outOfSRGBIndices {
            let expected = Self.expected(camera: Self.cameraValues[index], baselineStops: 0)
            #expect(expected.min() < 0)
            #expect(developed.means[index].min() < 0, "out-of-sRGB patch \(index) lost its negative component")
        }
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func previewDevelopMatchesFullDevelop(_ mosaic: SyntheticDNG.Mosaic) throws {
        let full = try Self.develop(mosaic, baselineStops: 2)
        let preview = try Self.develop(mosaic, baselineStops: 2, maxDimension: CGFloat(Self.chart.width / 2))
        // A draft RAW decode may come back larger than asked, so only bound the size.
        #expect((Self.chart.width / 2..<Self.chart.width).contains(Int(preview.negative.size.width)))
        #expect(full.means.contains { $0.max() > 1 })
        let worst = zip(preview.means, full.means).map { abs($0 - $1).max() / max(1, abs($1).max()) }.max() ?? .nan
        #expect(worst < Self.previewTolerance, "worst difference \(worst)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func developedRAWRendersFinite(_ mosaic: SyntheticDNG.Mosaic) throws {
        let developed = try Self.develop(mosaic, baselineStops: Self.headroomBaselineStops)
        #expect(developed.maxValue > RAWDevelopSupport.headroomFloor)
        #expect(developed.means.contains { $0.min() < 0 })
        var textured = Adjustments()
        textured.seed = 7
        for adjustments in [Adjustments.neutral, textured] {
            let output = try Self.renderer.render(developed.negative, adjustments)
            let values = Fixtures.encodedFloats(output, space: Renderer.outputSpace).flatMap { [$0.x, $0.y, $0.z] }
            #expect(values.allSatisfy { $0.isFinite })
            #expect(values.allSatisfy { (0...1).contains($0) }, "range \(values.min() ?? .nan)…\(values.max() ?? .nan)")
        }
    }
}
