import CoreImage
import EmulsionFixtures
import Foundation
import simd

@testable import EmulsionCore

enum RAWDevelopSupport {
    static let samplesFolders = TestEnvironment.rawSamples.value

    static let previewLongEdge: CGFloat = 1024

    /// Two stops above the old ceiling of 1.0.
    static let headroomFloor = 4.0

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

    /// With the Developer's DNG type hint: ImageIO types many ProRAW files in memory as TIFF.
    static func filter(_ data: Data) throws -> CIRAWFilter {
        guard let raw = CIRAWFilter(imageData: data, identifierHint: Developer.dngTypeIdentifier) else {
            throw EmulsionError.unsupportedPhoto
        }
        return raw
    }

    struct Developed {
        var negative: Negative
        var pixels: [SIMD3<Double>]
        var means: [SIMD3<Double>]
        var maxValue: Double { RAWDevelopSupport.maxValue(pixels) }

        init(chart: PatchChart, _ negative: Negative) {
            self.negative = negative
            pixels = Fixtures.linear(negative.image)
            means = chart.means(of: pixels, width: Int(negative.size.width), height: Int(negative.size.height))
        }
    }

    /// Apple's decode as the develop configures it, before the develop's half-float buffer: the decoder measured at
    /// float precision (`developIsTheDecodeInHalfFloat` bounds the buffer's rounding).
    static func decoded(
        _ data: Data, chart: PatchChart, maxDimension: CGFloat? = nil, whiteBalance: CameraWhiteBalance? = nil,
        anchor: ExposureAnchor.Choice = .measured
    ) throws -> Developed {
        Developed(chart: chart, try decode(data, maxDimension: maxDimension, whiteBalance: whiteBalance, anchor: anchor))
    }

    /// Measured worst 9.5e-4 (relative to the larger of the value and `halfFloatFloor`); a half-float step is 2^-10.
    static let halfFloatTolerance = 0.002
    static let halfFloatFloor = 0.01
    static let rendererLikeContext = CIContext(options: Renderer.contextOptions)

    /// Linear values read through a context with the renderer's options (half-float working format), bottom row first.
    static func linearThroughRendererContext(_ image: CIImage) -> [SIMD3<Double>] {
        RAWDevelopProbe.rgba(image, context: rendererLikeContext).map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
    }

    static func decode(
        _ data: Data, maxDimension: CGFloat? = nil, whiteBalance: CameraWhiteBalance? = nil, anchor: ExposureAnchor.Choice = .measured
    ) throws -> Negative {
        guard let decoder = RAWDevelopTests.developer.rawDecoder(data, maxDimension: maxDimension, anchor: anchor) else {
            throw EmulsionError.unsupportedPhoto
        }
        return try decoder.decode(whiteBalance: whiteBalance)
    }

    static func worstRelativeDifference(
        _ a: some Sequence<SIMD3<Double>>, _ b: some Sequence<SIMD3<Double>>, floor: Double
    ) -> Double {
        zip(a, b).map { (abs($0 - $1) / max(abs($1), SIMD3(repeating: floor))).max() }.max() ?? .nan
    }

    static func luminance(_ c: SIMD3<Double>) -> Double { (SyntheticDNG.xyzFromLinearSRGB * c).y }

    /// max(|R/G − 1|, |B/G − 1|).
    static func neutralError(_ c: SIMD3<Double>) -> Double { max(abs(c.x / c.y - 1), abs(c.z / c.y - 1)) }

    static func maxValue(_ pixels: [SIMD3<Double>]) -> Double { pixels.map { $0.max() }.max() ?? .nan }

    struct FrameStats {
        let maxValue: Double
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

    /// The Developer's RAW settings before MOV-79, frozen for before/after comparisons.
    static func applyPreMOV79Develop(_ raw: CIRAWFilter) {
        raw.boostAmount = 0
        raw.boostShadowAmount = 0
        if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
        if raw.isContrastSupported { raw.contrastAmount = 0 }
        raw.extendedDynamicRangeAmount = 0
    }

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
    var fourDigits: String { String(format: "%.4g", self) }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

extension SIMD3<Double> {
    var fourDigits: String { "(\(x.fourDigits), \(y.fourDigits), \(z.fourDigits))" }
}
