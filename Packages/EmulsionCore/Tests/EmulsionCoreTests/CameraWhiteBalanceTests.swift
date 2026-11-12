import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// RAW white balance (MOV-10) on synthetic DNGs of the wide-gamut camera: a chart lit by a
/// 2856 K Planckian light, tagged with that light or wrongly with D65. The independent
/// reference is the light's Planckian chromaticity (Kim et al. 2002).
struct CameraWhiteBalanceTests {
    static var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    static var developer: Developer { renderer.developer }

    static let tungstenKelvin = SyntheticDNG.illuminantAKelvin
    static let tungsten = SyntheticDNG.planckianChromaticity(kelvin: tungstenKelvin)
    static let d65 = SyntheticDNG.d65Chromaticity
    /// D65 at its CCT, 6504 K (CIE 15:2004).
    static let d65Kelvin = 6504.0

    static let neutralScene = [0.045, 0.09, 0.18, 0.36].map { SIMD3<Double>(repeating: $0) }
    static let scene = neutralScene + RAWDevelopChart.chromaticScene
    static let neutralIndices = neutralScene.indices
    static let chromaticIndices = neutralScene.count..<scene.count
    static let chart = PatchChart(scene)

    static func tungstenScene(_ mosaic: SyntheticDNG.Mosaic, taggedLight: SIMD2<Double>) -> Data {
        RAWDevelopChart.dng(mosaic, chart: chart, light: tungsten, taggedLight: taggedLight)
    }

    static func develop(
        _ data: Data, _ whiteBalance: CameraWhiteBalance? = nil, chart: PatchChart = chart, maxDimension: CGFloat? = nil
    ) throws -> RAWDevelopSupport.Developed {
        try RAWDevelopSupport.develop(data, chart: chart, maxDimension: maxDimension, whiteBalance: whiteBalance)
    }

    static func worstNeutralError(_ means: [SIMD3<Double>]) -> Double {
        neutralIndices.map { RAWDevelopSupport.neutralError(means[$0]) }.max() ?? .nan
    }

    /// Relative to the larger of this and the reference value: chromatic patches have channels near 0.
    static let relativeFloor = 0.01

    // MARK: Tolerances (about 2× the worst value measured on macOS 27.2, Bayer and linear files)

    /// Measured worst 6.8 K (2862.8 K read for 2856 K; 6502.0 K for 6504 K).
    static let asShotTemperatureTolerance = 15.0
    /// Measured worst 0.25 from the expected tint (0.25 for 2856 K; 9.77 for D65, expected 9.52).
    static let asShotTintTolerance = 0.5
    /// Measured worst 0.0012 (max |R/G − 1|, |B/G − 1|) on the gray patches.
    static let taggedNeutralTolerance = 0.0025
    /// The wrongly tagged file as shot: measured worst neutral error 1.22; a cast at least this large.
    static let wrongTagCast = 1.0
    /// Measured worst 0.0053 on the gray patches at 2856 K, tint 0.
    static let correctedNeutralTolerance = 0.011
    /// Measured worst 0.0183 (relative, any channel; chromatic patches, gray 0.0053) between the
    /// develop at 2856 K, tint 0, and the correctly tagged file: Apple reads that file as 2862.8 K.
    static let correctedMatchTolerance = 0.037
    /// Measured worst 0.0056 (Bayer; linear 2.5e-5) at the temperature and tint read from the
    /// correctly tagged file.
    static let readBackMatchTolerance = 0.012
    /// Measured worst 7.4e-6 (absolute, any channel and pixel) setting the as-shot values back.
    static let asShotRepeatTolerance = 2e-5
    /// Measured worst 0.0009 (relative to max(1, value)), draft half size vs full.
    static let previewTolerance = 0.002

    /// Apple's tint is the light's distance from the Planckian locus (Duv, CIE 1960 uv) × 3000,
    /// positive above the locus (green light, magenta correction): the scale of the DNG SDK's
    /// `dng_temperature` (|kTintScale| = 3000). Measured here, not documented by Apple.
    static let tintPerDuv = 3000.0

    /// Duv of a chromaticity from the Planckian locus at `kelvin`, its CCT.
    static func duv(_ xy: SIMD2<Double>, kelvin: Double) -> Double {
        func uv(_ c: SIMD2<Double>) -> SIMD2<Double> { SIMD2(4 * c.x, 6 * c.y) / (-2 * c.x + 12 * c.y + 3) }
        let offset = uv(xy) - uv(SyntheticDNG.planckianChromaticity(kelvin: kelvin))
        return (offset.y >= 0 ? 1 : -1) * simd_length(offset)
    }

    // MARK: As shot

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func asShotWhiteBalanceReadsTheTaggedLight(_ mosaic: SyntheticDNG.Mosaic) throws {
        for (tag, kelvin) in [(Self.tungsten, Self.tungstenKelvin), (Self.d65, Self.d65Kelvin)] {
            let data = Self.tungstenScene(mosaic, taggedLight: tag)
            let asShot = try #require(try Self.developer.develop(data).asShotWhiteBalance)
            let balanced = try Self.developer.develop(data, whiteBalance: CameraWhiteBalance(temperature: 4000, tint: 20))
            #expect(balanced.asShotWhiteBalance == asShot, "reports the file's white balance, not the one it was developed at")
            #expect(abs(asShot.temperature - kelvin) < Self.asShotTemperatureTolerance, "\(asShot.temperature) K for \(kelvin) K")
            let expectedTint = Self.tintPerDuv * Self.duv(tag, kelvin: kelvin)
            #expect(abs(asShot.tint - expectedTint) < Self.asShotTintTolerance, "tint \(asShot.tint), expected \(expectedTint)")
        }
        let jpeg = try Self.renderer.export(SceneFixtures.flat(0.18, width: 64, height: 64), format: .jpeg)
        #expect(try Self.developer.develop(jpeg).asShotWhiteBalance == nil)
    }

    @Test func resizingAndMaterializingKeepTheAsShotWhiteBalance() throws {
        let negative = try Self.developer.develop(Self.tungstenScene(.linearRGB, taggedLight: Self.tungsten))
        let asShot = try #require(negative.asShotWhiteBalance)
        #expect(Self.renderer.resized(negative, longestEdge: 64).asShotWhiteBalance == asShot)
        #expect(try Self.renderer.materialize(negative).asShotWhiteBalance == asShot)
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func asShotDevelopIsNeutralWhenTheTagIsRight(_ mosaic: SyntheticDNG.Mosaic) throws {
        let developed = try Self.develop(Self.tungstenScene(mosaic, taggedLight: Self.tungsten))
        let worst = Self.worstNeutralError(developed.means)
        #expect(worst < Self.taggedNeutralTolerance, "worst neutral error \(worst)")
    }

    // MARK: Correcting the white balance

    /// True RAW white balance: a tungsten scene the camera tagged as daylight develops neutral once
    /// told the light was 2856 K, and like the file tagged correctly, chromatic patches included.
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func whiteBalanceCorrectsAWrongTag(_ mosaic: SyntheticDNG.Mosaic) throws {
        let wrong = Self.tungstenScene(mosaic, taggedLight: Self.d65)
        let asShot = try Self.develop(wrong)
        let corrected = try Self.develop(wrong, CameraWhiteBalance(temperature: Self.tungstenKelvin, tint: 0))
        let reference = try Self.develop(Self.tungstenScene(mosaic, taggedLight: Self.tungsten))
        let cast = Self.worstNeutralError(asShot.means)
        let neutral = Self.worstNeutralError(corrected.means)
        let grayMatch = RAWDevelopSupport.worstRelativeDifference(
            corrected.means[Self.neutralIndices], reference.means[Self.neutralIndices], floor: Self.relativeFloor)
        let chromaticMatch = RAWDevelopSupport.worstRelativeDifference(
            corrected.means[Self.chromaticIndices], reference.means[Self.chromaticIndices], floor: Self.relativeFloor)
        let readBack = try #require(reference.negative.asShotWhiteBalance)
        let matched = try Self.develop(wrong, readBack)
        let readBackMatch = RAWDevelopSupport.worstRelativeDifference(matched.means, reference.means, floor: Self.relativeFloor)
        #expect(cast > Self.wrongTagCast, "as-shot neutral error \(cast)")
        #expect(neutral < Self.correctedNeutralTolerance, "corrected neutral error \(neutral)")
        #expect(grayMatch < Self.correctedMatchTolerance, "gray patches differ from the correct tag by \(grayMatch)")
        #expect(chromaticMatch < Self.correctedMatchTolerance, "chromatic patches differ from the correct tag by \(chromaticMatch)")
        #expect(readBackMatch < Self.readBackMatchTolerance, "at the read-back white balance: \(readBackMatch)")
    }

    static let sweepKelvins = [2500.0, 3200, 4000, 5000, 6500, 8000, 10000]

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func higherTemperatureWarmsTheRender(_ mosaic: SyntheticDNG.Mosaic) throws {
        let data = Self.tungstenScene(mosaic, taggedLight: Self.d65)
        let grays = try Self.sweepKelvins.map { kelvin in
            try Self.develop(data, CameraWhiteBalance(temperature: kelvin, tint: 0)).means[2]
        }
        for (cooler, warmer) in zip(grays, grays.dropFirst()) {
            #expect(warmer.x / warmer.y > cooler.x / cooler.y, "R/G \(cooler) → \(warmer)")
            #expect(warmer.z / warmer.y < cooler.z / cooler.y, "B/G \(cooler) → \(warmer)")
        }
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func positiveTintRendersMagenta(_ mosaic: SyntheticDNG.Mosaic) throws {
        let data = Self.tungstenScene(mosaic, taggedLight: Self.tungsten)
        let grays = try [-50.0, 0, 50].map { tint in
            try Self.develop(data, CameraWhiteBalance(temperature: Self.tungstenKelvin, tint: tint)).means[2]
        }
        for (greener, magenta) in zip(grays, grays.dropFirst()) {
            #expect(magenta.y / magenta.x < greener.y / greener.x, "G/R \(greener) → \(magenta)")
            #expect(magenta.y / magenta.z < greener.y / greener.z, "G/B \(greener) → \(magenta)")
        }
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func settingTheAsShotValuesChangesNothing(_ mosaic: SyntheticDNG.Mosaic) throws {
        for tag in [Self.tungsten, Self.d65] {
            let data = Self.tungstenScene(mosaic, taggedLight: tag)
            let plain = try Self.develop(data)
            let explicit = try Self.develop(data, try #require(plain.negative.asShotWhiteBalance))
            let worst = zip(plain.pixels, explicit.pixels).map { abs($0 - $1).max() }.max() ?? .nan
            #expect(worst < Self.asShotRepeatTolerance, "worst difference \(worst)")
        }
    }

    @Test func whiteBalanceIsClamped() throws {
        let below = CameraWhiteBalance(temperature: 500, tint: -400)
        let above = CameraWhiteBalance(temperature: 90_000, tint: 400)
        #expect(below.clamped() == CameraWhiteBalance(temperature: 2000, tint: -150))
        #expect(above.clamped() == CameraWhiteBalance(temperature: 50_000, tint: 150))
        let inside = CameraWhiteBalance(temperature: 3200, tint: 12)
        #expect(inside.clamped() == inside)
        var adjustments = Adjustments()
        adjustments.whiteBalance = above
        #expect(adjustments.clamped().whiteBalance == above.clamped())

        let data = Self.tungstenScene(.linearRGB, taggedLight: Self.d65)
        for value in [below, above] {
            let outOfRange = try Self.develop(data, value)
            let atTheEnd = try Self.develop(data, value.clamped())
            #expect(outOfRange.pixels == atTheEnd.pixels, "\(value) develops unlike \(value.clamped())")
        }
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func previewAndFullDevelopAgreeWithWhiteBalance(_ mosaic: SyntheticDNG.Mosaic) throws {
        let data = Self.tungstenScene(mosaic, taggedLight: Self.d65)
        let whiteBalance = CameraWhiteBalance(temperature: 3200, tint: 10)
        let full = try Self.develop(data, whiteBalance)
        let preview = try Self.develop(data, whiteBalance, maxDimension: CGFloat(Self.chart.width / 2))
        #expect(preview.negative.size.width < full.negative.size.width)
        let worst = RAWDevelopSupport.worstRelativeDifference(preview.means, full.means, floor: 1)
        #expect(worst < Self.previewTolerance, "worst difference \(worst)")
    }

    // MARK: Separate from the exposure anchor and the print

    /// On a "48 MP-like" profile file the anchor is measured at the as-shot white balance, so it
    /// is the same whatever white balance develops the image; values above 1.0 keep their headroom.
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func whiteBalanceLeavesTheExposureAnchorAlone(_ mosaic: SyntheticDNG.Mosaic) throws {
        let chart = ExposureAnchorDevelopTests.chart
        let data = RAWDevelopChart.dng(
            mosaic, chart: chart, baselineStops: ExposureAnchorDevelopTests.fortyEightBaselineStops,
            profile: ExposureAnchorDevelopTests.fortyEight)
        let asShot = try Self.develop(data, chart: chart)
        let anchor = asShot.negative.exposureAnchorStops
        #expect(anchor != 0)
        let brightest = try #require(RAWDevelopChart.neutralIndices.last)
        for whiteBalance in [
            CameraWhiteBalance(temperature: 3200, tint: 0), CameraWhiteBalance(temperature: 6500, tint: 20),
            CameraWhiteBalance(temperature: 10000, tint: -20),
        ] {
            let developed = try Self.develop(data, whiteBalance, chart: chart)
            #expect(developed.negative.exposureAnchorStops == anchor, "\(whiteBalance): \(developed.negative.exposureAnchorStops)")
            let top = developed.means[brightest]
            #expect(top.y > 1 && top.max() > 1.5, "\(whiteBalance): brightest neutral \(top) clipped at 1.0")
        }
    }

    @Test func whiteBalanceIsIgnoredForDisplayReferredPhotos() throws {
        let data = try Self.renderer.export(SceneFixtures.patches(), format: .jpeg)
        let plain = try Self.developer.develop(data)
        let balanced = try Self.developer.develop(data, whiteBalance: CameraWhiteBalance(temperature: 3200, tint: 30))
        #expect(balanced.contract == .displayReferred)
        #expect(Fixtures.linear(plain.image) == Fixtures.linear(balanced.image))
    }

    /// White balance acts at develop; Warmth and Tint are printer lights, at print.
    @Test func printerLightsStaySeparate() throws {
        let negative = try Self.develop(Self.tungstenScene(.linearRGB, taggedLight: Self.tungsten)).negative
        var balanced = Adjustments.neutral
        balanced.whiteBalance = CameraWhiteBalance(temperature: 3200, tint: 30)
        let plain = Fixtures.linear(try Self.renderer.render(negative, .neutral))
        #expect(Fixtures.linear(try Self.renderer.render(negative, balanced)) == plain)
        var warmer = Adjustments.neutral
        warmer.warmth = 0.5
        #expect(Fixtures.linear(try Self.renderer.render(negative, warmer)) != plain)
    }
}

// MARK: Real files (opt-in)

/// RAW white balance on real DNGs from EMULSION_RAW_SAMPLES (never checked in). Re-saved files
/// whose AsShotNeutral is [1, 1, 1] only test the mechanism, not the camera's white balance.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct CameraWhiteBalanceRealFileTests {
    /// Measured worst 1.6e-4 (any channel and pixel, relative to max(1, value), 1024 px; absolute
    /// 0.0024 on a file anchored +2.95 stops) setting the as-shot values back.
    static let asShotRepeatTolerance = 4e-4
    static let cool = 3200.0
    static let daylight = 6500.0

    /// Mean R/G and B/G over the frame.
    static func ratios(_ pixels: [SIMD3<Double>]) -> SIMD2<Double> {
        let mean = pixels.reduce(SIMD3<Double>.zero, +) / Double(pixels.count)
        return SIMD2(mean.x / mean.y, mean.z / mean.y)
    }

    @Test func realFilesFollowTheWhiteBalance() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        let developer = RAWDevelopTests.developer
        let edge = RAWDevelopSupport.previewLongEdge
        print(
            "| File | As shot K | Tint | R/G, B/G as shot | R/G, B/G \(Int(Self.cool)) K | R/G, B/G \(Int(Self.daylight)) K"
                + " | Max rel. diff, as-shot values set | Anchor (as shot / \(Int(Self.cool)) / \(Int(Self.daylight))) |")
        print("| --- | ---: | ---: | --- | --- | --- | ---: | --- |")
        var worstRepeat = 0.0
        for url in urls {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let plain = try developer.develop(data, maxDimension: edge)
            let asShot = try #require(plain.asShotWhiteBalance, "\(name) is not RAW")
            let explicit = try developer.develop(data, maxDimension: edge, whiteBalance: asShot)
            let cool = try developer.develop(
                data, maxDimension: edge, whiteBalance: CameraWhiteBalance(temperature: Self.cool, tint: asShot.tint))
            let daylight = try developer.develop(
                data, maxDimension: edge, whiteBalance: CameraWhiteBalance(temperature: Self.daylight, tint: asShot.tint))
            let plainPixels = Fixtures.linear(plain.image)
            let repeatDifference =
                zip(plainPixels, Fixtures.linear(explicit.image)).map { abs($0 - $1).max() / max(1, abs($0).max()) }.max() ?? .nan
            worstRepeat = max(worstRepeat, repeatDifference)
            let (shotRatios, coolRatios, daylightRatios) = (
                Self.ratios(plainPixels), Self.ratios(Fixtures.linear(cool.image)), Self.ratios(Fixtures.linear(daylight.image))
            )
            func pair(_ r: SIMD2<Double>) -> String { "\(r.x.fourDigits), \(r.y.fourDigits)" }
            let anchors = [plain, cool, daylight].map { String(format: "%+.4f", $0.exposureAnchorStops) }.joined(separator: " / ")
            print(
                "| \(name) | \(asShot.temperature.fourDigits) | \(asShot.tint.fourDigits) | \(pair(shotRatios)) | \(pair(coolRatios))"
                    + " | \(pair(daylightRatios)) | \(repeatDifference.fourDigits) | \(anchors) |")
            #expect(repeatDifference <= Self.asShotRepeatTolerance, "\(name): \(repeatDifference)")
            #expect(cool.exposureAnchorStops == plain.exposureAnchorStops, "\(name): anchor moved at \(Self.cool) K")
            #expect(daylight.exposureAnchorStops == plain.exposureAnchorStops, "\(name): anchor moved at \(Self.daylight) K")
            #expect(
                coolRatios.x / coolRatios.y < daylightRatios.x / daylightRatios.y,
                "\(name): R/B at \(Self.cool) K is not below \(Self.daylight) K")
        }
        print("worst difference setting the as-shot values back: \(worstRepeat.fourDigits)")
    }
}

// MARK: Proof renders (opt-in)

extension RAWDevelopProofRenders {
    /// MOV-10: the tungsten chart tagged as daylight, as shot and at 2856 K, with the correctly
    /// tagged file as the reference; the CC0 real files as shot, cooler and warmer.
    @Test func writesWhiteBalanceRenders() throws {
        let folder = try Self.outputFolder()
        let developer = RAWDevelopTests.developer
        let chart = PatchChart(CameraWhiteBalanceTests.scene, cell: 80)
        let tungsten = CameraWhiteBalanceTests.tungsten
        let wrong = RAWDevelopChart.dng(.bayerRGGB, chart: chart, light: tungsten, taggedLight: CameraWhiteBalanceTests.d65)
        let right = RAWDevelopChart.dng(.bayerRGGB, chart: chart, light: tungsten, taggedLight: tungsten)
        let corrected = CameraWhiteBalance(temperature: CameraWhiteBalanceTests.tungstenKelvin, tint: 0)
        try Self.write(developer.develop(wrong), to: folder.appendingPathComponent("wb-wrong-tag-before.png"))
        try Self.write(developer.develop(wrong, whiteBalance: corrected), to: folder.appendingPathComponent("wb-wrong-tag-after.png"))
        try Self.write(developer.develop(right), to: folder.appendingPathComponent("wb-right-tag-reference.png"))

        for url in try Self.cc0Samples() {
            let name = url.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: url)
            let asShot = try #require(try developer.develop(data, maxDimension: Self.longEdge).asShotWhiteBalance)
            for (label, factor) in [("as-shot", 1.0), ("cooler", 0.75), ("warmer", 1.35)] {
                let whiteBalance = CameraWhiteBalance(temperature: asShot.temperature * factor, tint: asShot.tint)
                print("\(name) \(label): \(whiteBalance.temperature) K, tint \(whiteBalance.tint)")
                try Self.write(
                    developer.develop(data, maxDimension: Self.longEdge, whiteBalance: factor == 1 ? nil : whiteBalance),
                    to: folder.appendingPathComponent("\(name)-wb-\(label).png"))
            }
        }
    }
}
