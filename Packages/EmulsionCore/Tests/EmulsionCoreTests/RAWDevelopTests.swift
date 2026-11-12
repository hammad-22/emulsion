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

    struct Developed {
        var negative: Negative
        var means: [SIMD3<Double>]
        var maxValue: Double
    }

    static func develop(_ mosaic: SyntheticDNG.Mosaic, baselineStops: Double, maxDimension: CGFloat? = nil) throws -> Developed {
        let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: baselineStops)
        let negative = try developer.develop(data, maxDimension: maxDimension)
        let pixels = Fixtures.linear(negative.image)
        let means = chart.means(of: pixels, width: Int(negative.size.width), height: Int(negative.size.height))
        return Developed(negative: negative, means: means, maxValue: RAWDevelopSupport.maxValue(pixels))
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

    // MARK: Tolerances (about 2× the worst value measured on macOS 27.2, Bayer and linear files)

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

    // MARK: Recognising DNG

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

    // MARK: Headroom

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

    // MARK: Linearity and neutrality

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

    // MARK: Colour

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

    // MARK: Preview and render

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

// MARK: Real files (opt-in)

/// Real DNGs from EMULSION_RAW_SAMPLES (never checked in): the pre-MOV-79 develop against today's.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct RAWDevelopRealFileTests {
    static let minimumFilesForHeadroomCheck = 20
    static let minimumFilesAboveFloor = 3
    /// The old develop's max may exceed the new one only by rounding.
    static let maxTolerance = 0.01

    @Test func developedRealFilesKeepHeadroom() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        let developer = RAWDevelopTests.developer
        print("| File | BaselineExposure | Old max | New max | New p99.9 lum | > 1 | > 2 | > 4 |")
        print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        var aboveFloor = 0
        for url in urls {
            let raw = try #require(CIRAWFilter(imageURL: url))
            let baseline = raw.baselineExposure
            let old = RAWDevelopSupport.FrameStats(
                Fixtures.linear(try RAWDevelopSupport.preMOV79Negative(raw, maxDimension: RAWDevelopSupport.previewLongEdge).image))
            let developed = try developer.develop(Data(contentsOf: url), maxDimension: RAWDevelopSupport.previewLongEdge)
            #expect(developed.contract == .sceneReferred, "\(url.lastPathComponent) did not develop as RAW")
            let new = RAWDevelopSupport.FrameStats(Fixtures.linear(developed.image))
            let name = url.lastPathComponent
            print(
                "| \(name) | \(Double(baseline).fourDigits) | \(old.maxValue.fourDigits) | \(new.maxValue.fourDigits) | \(new.p999.fourDigits)"
                    + " | \(new.over1.fourDigits) | \(new.over2.fourDigits) | \(new.over4.fourDigits) |"
            )
            #expect(old.isFinite && new.isFinite, "\(name) has non-finite values")
            #expect(new.maxValue >= old.maxValue - Self.maxTolerance, "\(name): new max \(new.maxValue) < old max \(old.maxValue)")
            if new.maxValue > RAWDevelopSupport.headroomFloor { aboveFloor += 1 }
        }
        if urls.count >= Self.minimumFilesForHeadroomCheck {
            #expect(
                aboveFloor >= Self.minimumFilesAboveFloor, "\(aboveFloor) of \(urls.count) files exceed \(RAWDevelopSupport.headroomFloor)")
        }
    }
}

// MARK: Exposure anchor on real files (opt-in)

/// The exposure anchor (MOV-134) on real DNGs from EMULSION_RAW_SAMPLES: anchored develops land
/// near Apple's default render in median luminance, whatever the file's megapixels.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct ExposureAnchorRealFileTests {
    /// Measured worst |log2(anchored median ÷ Apple median)| 0.576 stops over 25 files (mean 0.168).
    static let appleMedianTolerance = 1.15
    /// Measured −0.017 stops: mean log2(anchored ÷ Apple) of files ≥ 40 MP minus files < 20 MP
    /// (before the anchor the 48 MP ProRAW files sat 2–3 stops below Apple's render).
    static let megapixelGapTolerance = 0.5
    static let largeMegapixels = 40.0
    static let smallMegapixels = 20.0
    static let secondPreviewLongEdge: CGFloat = 512
    static let anchorRepeatTolerance = 1e-6

    static func medianLuminance(_ image: CIImage) -> Double {
        RAWDevelopSupport.FrameStats(Fixtures.linear(image)).medianLuminance
    }

    /// Apple's default render (every CIRAWFilter default) at the preview size.
    static func appleDefault(_ data: Data, maxDimension: CGFloat) throws -> CIImage {
        let raw = try RAWDevelopSupport.filter(data)
        Developer.applyPreviewScale(raw, maxDimension: maxDimension, allowsDraftMode: false)
        return try #require(raw.outputImage)
    }

    @Test func anchoredDevelopsMatchApplesMidtones() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        let developer = RAWDevelopTests.developer
        let edge = RAWDevelopSupport.previewLongEdge
        print("| File | MP | BaselineExposure | Anchor (stops) | Median before | Median after | Median Apple | log2(after ÷ Apple) |")
        print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        var gaps: [(megapixels: Double, stops: Double)] = []
        for url in urls {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let raw = try RAWDevelopSupport.filter(data)
            let megapixels = Double(raw.nativeSize.width * raw.nativeSize.height) / 1e6
            let before = try developer.develop(data, maxDimension: edge, anchor: .none)
            let after = try developer.develop(data, maxDimension: edge)
            let again = try developer.develop(data, maxDimension: Self.secondPreviewLongEdge)
            let anchor = after.exposureAnchorStops
            let (beforeMedian, afterMedian) = (Self.medianLuminance(before.image), Self.medianLuminance(after.image))
            let appleMedian = Self.medianLuminance(try Self.appleDefault(data, maxDimension: edge))
            let gap = log2(afterMedian / appleMedian)
            gaps.append((megapixels, gap))
            print(
                "| \(name) | \(megapixels.fourDigits) | \(Double(raw.baselineExposure).fourDigits) | \(String(format: "%+.3f", anchor))"
                    + " | \(beforeMedian.fourDigits) | \(afterMedian.fourDigits) | \(appleMedian.fourDigits) | \(String(format: "%+.3f", gap)) |"
            )
            #expect(anchor.isFinite && ExposureAnchor.range.contains(anchor), "\(name): anchor \(anchor)")
            let repeated = again.exposureAnchorStops
            #expect(abs(repeated - anchor) <= Self.anchorRepeatTolerance, "\(name): \(repeated) at 512 px vs \(anchor) at 1024 px")
            #expect(abs(gap) <= Self.appleMedianTolerance, "\(name): log2(after ÷ Apple) \(gap)")
        }
        let large = gaps.filter { $0.megapixels >= Self.largeMegapixels }.map(\.stops)
        let small = gaps.filter { $0.megapixels < Self.smallMegapixels }.map(\.stops)
        let worst = gaps.map { abs($0.stops) }.max() ?? .nan
        let meanAbs = gaps.map { abs($0.stops) }.reduce(0, +) / Double(gaps.count)
        print("worst |log2(after ÷ Apple)| \(worst.fourDigits), mean \(meanAbs.fourDigits) stops")
        if urls.count >= RAWDevelopRealFileTests.minimumFilesForHeadroomCheck, !large.isEmpty, !small.isEmpty {
            let gap = large.reduce(0, +) / Double(large.count) - small.reduce(0, +) / Double(small.count)
            print("≥ \(Self.largeMegapixels) MP minus < \(Self.smallMegapixels) MP: \(String(format: "%+.3f", gap)) stops")
            #expect(abs(gap) <= Self.megapixelGapTolerance, "megapixel gap \(gap)")
        }
    }
}

// MARK: Proof renders (opt-in)

/// Before/after PNGs through the neutral film look for the PRs (MOV-79, MOV-134). EMULSION_PROOF_DIR
/// names the output folder. Real files: only the CC0 samples (names ending in `_CC0.dng`) are rendered.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"] != nil), .serialized)
struct RAWDevelopProofRenders {
    /// Small enough to keep each PNG to a few hundred KB.
    static let longEdge: CGFloat = 640
    static let wedgeBaselineStops = 2.0

    static func write(_ negative: Negative, to url: URL) throws {
        try EmulsionTestCase.writePNG(RAWDevelopTests.renderer.render(negative, .neutral), to: url)
    }

    static func cc0Samples() throws -> [URL] {
        try RAWDevelopSupport.sampleURLs().filter { $0.lastPathComponent.lowercased().hasSuffix("_cc0.dng") }
    }

    static func outputFolder() throws -> URL {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"]), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func writesBeforeAfterRenders() throws {
        let folder = try Self.outputFolder()
        let developer = RAWDevelopTests.developer

        let chart = RAWDevelopChart.chart(cell: 96)
        let wedge = RAWDevelopChart.dng(.bayerRGGB, chart: chart, baselineStops: Self.wedgeBaselineStops)
        let wedgeFilter = try #require(CIRAWFilter(imageData: wedge, identifierHint: nil))
        try Self.write(RAWDevelopSupport.preMOV79Negative(wedgeFilter), to: folder.appendingPathComponent("wedge-before.png"))
        try Self.write(developer.develop(wedge), to: folder.appendingPathComponent("wedge-after.png"))

        for url in try Self.cc0Samples() {
            let name = url.deletingPathExtension().lastPathComponent
            let raw = try #require(CIRAWFilter(imageURL: url))
            try Self.write(
                RAWDevelopSupport.preMOV79Negative(raw, maxDimension: Self.longEdge),
                to: folder.appendingPathComponent("\(name)-before.png"))
            try Self.write(
                developer.develop(Data(contentsOf: url), maxDimension: Self.longEdge),
                to: folder.appendingPathComponent("\(name)-after.png"))
        }
    }

    /// MOV-134: before is the develop without the exposure anchor, after is with it.
    @Test func writesExposureAnchorRenders() throws {
        let folder = try Self.outputFolder()
        let developer = RAWDevelopTests.developer
        for url in try Self.cc0Samples() {
            let name = url.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: url)
            try Self.write(
                developer.develop(data, maxDimension: Self.longEdge, anchor: .none),
                to: folder.appendingPathComponent("\(name)-anchor-before.png"))
            let anchored = try developer.develop(data, maxDimension: Self.longEdge)
            print("\(name): exposure anchor \(String(format: "%+.3f", anchored.exposureAnchorStops)) stops")
            try Self.write(anchored, to: folder.appendingPathComponent("\(name)-anchor-after.png"))
        }
    }
}
