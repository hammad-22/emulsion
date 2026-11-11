import CoreImage
import Foundation
import simd

@testable import EmulsionCore

/// Helpers shared by `RAWDevelopTests` and `RAWDevelopProbe`.
enum RAWDevelopSupport {
    /// ":"-separated folders of real DNGs (opt-in; real samples never enter the repo).
    static let samplesFolders = ProcessInfo.processInfo.environment["EMULSION_RAW_SAMPLES"]

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

    /// Highlight statistics of a developed frame (linear sRGB pixels).
    struct FrameStats {
        var max: SIMD3<Double>
        var min: Double
        var median: Double
        var p999: Double
        var mean: SIMD3<Double>
        /// Fractions of pixels whose brightest channel exceeds 1, 2 and 4.
        var over1: Double
        var over2: Double
        var over4: Double
        /// Mean R/G and B/G of the brightest 0.1 % of pixels by luminance: the colour of clipped highlights.
        var highlightRatios: SIMD2<Double>
        var isFinite: Bool

        static func luminance(_ c: SIMD3<Double>) -> Double { 0.2126729 * c.x + 0.7151522 * c.y + 0.0721750 * c.z }

        init(_ pixels: [SIMD3<Double>]) {
            let sortedLuminance = pixels.map(Self.luminance).sorted()
            let count = Double(pixels.count)
            max = pixels.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) }
            min = pixels.map { $0.min() }.min() ?? .nan
            median = sortedLuminance[sortedLuminance.count / 2]
            p999 = sortedLuminance[Swift.min(sortedLuminance.count - 1, Int(count * 0.999))]
            mean = pixels.reduce(SIMD3<Double>.zero, +) / count
            over1 = Double(pixels.filter { $0.max() > 1 }.count) / count
            over2 = Double(pixels.filter { $0.max() > 2 }.count) / count
            over4 = Double(pixels.filter { $0.max() > 4 }.count) / count
            let threshold = p999
            let brightest = pixels.filter { Self.luminance($0) >= threshold }
            let brightMean = brightest.reduce(SIMD3<Double>.zero, +) / Double(Swift.max(brightest.count, 1))
            highlightRatios = SIMD2(brightMean.x / brightMean.y, brightMean.z / brightMean.y)
            isFinite = pixels.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        }

        var maxValue: Double { max.max() }
    }

    /// The Developer's RAW configuration before MOV-79: Apple's look processing off, gamut
    /// mapping, shadow bias and highlight recovery at the file's defaults.
    static func applyPreMOV79Develop(_ raw: CIRAWFilter) {
        raw.boostAmount = 0
        raw.boostShadowAmount = 0
        if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
        if raw.isContrastSupported { raw.contrastAmount = 0 }
        raw.extendedDynamicRangeAmount = 0
    }

    /// A negative developed with the pre-MOV-79 configuration, for before/after comparisons.
    static func preMOV79Negative(_ raw: CIRAWFilter, maxDimension: CGFloat? = nil) throws -> Negative {
        applyPreMOV79Develop(raw)
        if let maxDimension {
            let scale = min(1, maxDimension / max(raw.nativeSize.width, raw.nativeSize.height))
            raw.scaleFactor = Float(scale)
            raw.isDraftModeEnabled = scale < 1
        }
        guard let output = raw.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else {
            throw EmulsionError.unsupportedPhoto
        }
        let e = output.extent.integral
        let image = output.cropped(to: e).transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        return Negative(image: image, contract: .sceneReferred)
    }
}
