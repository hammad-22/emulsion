import CoreImage
import EmulsionFixtures
import Foundation
import simd

@testable import EmulsionCore

/// Helpers shared by the RAW develop, exposure anchor and white balance tests and `RAWDevelopProbe`.
enum RAWDevelopSupport {
    /// ":"-separated folders of real DNGs (opt-in; real samples never enter the repo).
    static let samplesFolders = ProcessInfo.processInfo.environment["EMULSION_RAW_SAMPLES"]

    /// Long edge of the scaled real-file decode, to keep 48 MP files fast.
    static let previewLongEdge: CGFloat = 1024

    /// A highlight that reaches 4.0 in scene light is two stops above the old ceiling of 1.0.
    static let headroomFloor = 4.0

    /// Every .dng (any case) in the folders of EMULSION_RAW_SAMPLES, sorted by name per folder.
    static func sampleURLs() throws -> [URL] {
        guard let samplesFolders else { return [] }
        return try samplesFolders.split(separator: ":").flatMap { path in
            try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: String(path), isDirectory: true), includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "dng" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    /// A CIRAWFilter for `data` with the DNG type hint the Developer uses (ImageIO types many
    /// ProRAW files read from memory as plain TIFF).
    static func filter(_ data: Data) throws -> CIRAWFilter {
        guard let raw = CIRAWFilter(imageData: data, identifierHint: Developer.dngTypeIdentifier) else {
            throw EmulsionError.unsupportedPhoto
        }
        return raw
    }

    /// A synthetic chart developed by the shared renderer: its pixels (linear sRGB) and patch means.
    struct Developed {
        var negative: Negative
        var pixels: [SIMD3<Double>]
        var means: [SIMD3<Double>]

        init(chart: PatchChart, _ negative: Negative) {
            self.negative = negative
            pixels = Fixtures.linear(negative.image)
            means = chart.means(of: pixels, width: Int(negative.size.width), height: Int(negative.size.height))
        }
    }

    static func develop(
        _ data: Data, chart: PatchChart, maxDimension: CGFloat? = nil, whiteBalance: CameraWhiteBalance? = nil,
        anchor: ExposureAnchor.Choice = .measured
    ) throws -> Developed {
        Developed(
            chart: chart,
            try RAWDevelopTests.developer.develop(data, maxDimension: maxDimension, whiteBalance: whiteBalance, anchor: anchor))
    }

    /// Largest channel difference between `a` and the reference `b`, relative to the larger of
    /// `floor` and the reference value.
    static func worstRelativeDifference(
        _ a: some Sequence<SIMD3<Double>>, _ b: some Sequence<SIMD3<Double>>, floor: Double
    ) -> Double {
        zip(a, b).map { (abs($0 - $1) / max(abs($1), SIMD3(repeating: floor))).max() }.max() ?? .nan
    }

    /// Rec. 709 / sRGB luminance (Y) of linear sRGB.
    static func luminance(_ c: SIMD3<Double>) -> Double { (SyntheticDNG.xyzFromLinearSRGB * c).y }

    /// How far a colour is from neutral: max(|R/G − 1|, |B/G − 1|).
    static func neutralError(_ c: SIMD3<Double>) -> Double { max(abs(c.x / c.y - 1), abs(c.z / c.y - 1)) }

    /// The brightest channel value over all pixels.
    static func maxValue(_ pixels: [SIMD3<Double>]) -> Double { pixels.map { $0.max() }.max() ?? .nan }

    /// Highlight statistics of a developed frame (linear sRGB pixels).
    struct FrameStats {
        let maxValue: Double
        /// 50th and 99.9th percentiles of luminance.
        let medianLuminance: Double
        let p999: Double
        /// Fractions of pixels whose brightest channel exceeds 1, 2 and 4.
        let over1: Double
        let over2: Double
        let over4: Double
        let isFinite: Bool

        init(_ pixels: [SIMD3<Double>]) {
            let sortedLuminance = pixels.map(luminance).sorted()
            let count = Double(pixels.count)
            maxValue = RAWDevelopSupport.maxValue(pixels)
            medianLuminance = sortedLuminance[sortedLuminance.count / 2]
            p999 = sortedLuminance[min(sortedLuminance.count - 1, Int(count * 0.999))]
            over1 = Double(pixels.count(where: { $0.max() > 1 })) / count
            over2 = Double(pixels.count(where: { $0.max() > 2 })) / count
            over4 = Double(pixels.count(where: { $0.max() > 4 })) / count
            isFinite = pixels.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        }
    }

    /// The Developer's RAW configuration before MOV-79, frozen here for before/after
    /// comparisons: Apple's look processing off, gamut mapping, shadow bias and highlight
    /// recovery at the file's defaults.
    static func applyPreMOV79Develop(_ raw: CIRAWFilter) {
        raw.boostAmount = 0
        raw.boostShadowAmount = 0
        if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
        if raw.isContrastSupported { raw.contrastAmount = 0 }
        raw.extendedDynamicRangeAmount = 0
    }

    /// A negative developed with the pre-MOV-79 configuration.
    static func preMOV79Negative(_ raw: CIRAWFilter, maxDimension: CGFloat? = nil) throws -> Negative {
        applyPreMOV79Develop(raw)
        Developer.applyPreviewScale(raw, maxDimension: maxDimension, allowsDraftMode: true)
        guard let output = raw.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else {
            throw EmulsionError.unsupportedPhoto
        }
        return Negative(image: Developer.normalized(output), contract: .sceneReferred)
    }
}

extension Double {
    /// Four significant digits, for probe and real-file tables.
    var fourDigits: String { String(format: "%.4g", self) }
}

extension Duration {
    /// Elapsed time in milliseconds, for probe timings.
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

extension SIMD3<Double> {
    var fourDigits: String { "(\(x.fourDigits), \(y.fourDigits), \(z.fourDigits))" }
}
