import Foundation
import simd

/// A deterministic synthetic DNG (TIFF/EP, little-endian, uncompressed, one strip, 16-bit) that
/// Apple's RAW decoder accepts. Camera values are linear, 1 = sensor white; values outside 0…1
/// clip, as a sensor does. Nothing here models a real camera: the colour matrices are synthetic.
public struct SyntheticDNG: Sendable {
    public enum Mosaic: Sendable, CaseIterable {
        /// One sample per pixel behind an RGGB colour filter array.
        case bayerRGGB
        /// Three demosaiced samples per pixel, the container ProRAW uses.
        case linearRGB

        /// TIFF/EP PhotometricInterpretation: CFA (32803) or DNG LinearRaw (34892).
        var photometricInterpretation: UInt16 { self == .bayerRGGB ? 32803 : 34892 }
        var samplesPerPixel: Int { self == .bayerRGGB ? 1 : 3 }
        /// DNGBackwardVersion: LinearRaw needs DNG 1.3.
        var backwardVersion: [UInt8] { self == .bayerRGGB ? [1, 1, 0, 0] : [1, 3, 0, 0] }
    }

    public let mosaic: Mosaic
    /// Pixels; even, so the RGGB pattern tiles the image.
    public let width: Int
    public let height: Int
    public let baselineExposureStops: Double
    /// Camera-space neutral (green = 1), DNG AsShotNeutral.
    public let asShotNeutral: SIMD3<Double>
    /// XYZ → camera, DNG ColorMatrix1 for CalibrationIlluminant1 = D65.
    public let cameraFromXYZ: simd_double3x3
    /// Rendering hints of the file's DNG profile; nil writes none.
    public let profile: Profile?

    /// A DNG profile's rendering hints, the tags Apple's 48 MP ProRAW uses to brighten its image.
    public struct Profile: Sendable {
        /// ProfileGainTableMap (DNG 1.6) holding one gain everywhere: every pixel, whatever its level.
        public let gainTableGain: Float
        /// ProfileToneCurve: (input, output) pairs from (0, 0) to (1, 1), linear in and out;
        /// identity by default.
        public let toneCurve: [SIMD2<Float>]

        public init(gainTableGain: Float, toneCurve: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 1)]) {
            self.gainTableGain = gainTableGain
            self.toneCurve = toneCurve
        }
    }

    /// 16-bit codes with no black offset: code 0 is no light, 65535 sensor white.
    private static let blackLevel = 0
    private static let whiteLevel = Int(UInt16.max)

    public init(
        mosaic: Mosaic, width: Int, height: Int, baselineExposureStops: Double = 0, asShotNeutral: SIMD3<Double>,
        cameraFromXYZ: simd_double3x3, profile: Profile? = nil
    ) {
        precondition(width > 0 && height > 0 && width.isMultiple(of: 2) && height.isMultiple(of: 2), "DNG size must be even")
        self.mosaic = mosaic
        self.width = width
        self.height = height
        self.baselineExposureStops = baselineExposureStops
        self.asShotNeutral = asShotNeutral
        self.cameraFromXYZ = cameraFromXYZ
        self.profile = profile
    }

    /// The file, padded with trailing zeros to `minimumFileSize`. `camera(x, y)` gives the
    /// camera-space linear value of a pixel, y = 0 the top row.
    public func data(_ camera: (Int, Int) -> SIMD3<Double>) -> Data {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * mosaic.samplesPerPixel * MemoryLayout<UInt16>.size)
        let span = Double(Self.whiteLevel - Self.blackLevel)
        for y in 0..<height {
            for x in 0..<width {
                let value = camera(x, y)
                let samples: [Double] =
                    switch mosaic {
                    case .bayerRGGB: [value[Self.rggbChannel(x: x, y: y)]]
                    case .linearRGB: [value.x, value.y, value.z]
                    }
                for sample in samples {
                    let code = UInt16(Double(Self.blackLevel) + (min(max(sample, 0), 1) * span).rounded())
                    pixels += code.littleEndianBytes
                }
            }
        }
        return TIFFWriter.file(entries: entries(stripByteCount: pixels.count), pixels: pixels, minimumSize: Self.minimumFileSize)
    }

    /// ImageIO identifies a TIFF with DNGVersion as DNG only from about 100 KiB (macOS 27.2:
    /// 101,862 bytes read as TIFF, 102,886 as DNG), so tests of Apple's decoder pad to this size.
    private static let minimumFileSize = 128 * 1024

    /// Row-major RGGB: red at even/even, blue at odd/odd.
    private static func rggbChannel(x: Int, y: Int) -> Int { (x % 2) + (y % 2) }

    /// CIRAWFilter needs NewSubFileType, PhotometricInterpretation, StripByteCounts, DNGVersion,
    /// ColorMatrix1, SamplesPerPixel, AsShotNeutral, BaselineExposure and the CFA pattern (macOS 27.2).
    private func entries(stripByteCount: Int) -> [TIFFEntry] {
        let samples = mosaic.samplesPerPixel
        var entries: [TIFFEntry] = [
            .long(.newSubFileType, [0]),
            .long(.imageWidth, [UInt32(width)]),
            .long(.imageLength, [UInt32(height)]),
            .short(.bitsPerSample, Array(repeating: 16, count: samples)),
            .short(.compression, [Self.uncompressed]),
            .short(.photometricInterpretation, [mosaic.photometricInterpretation]),
            .ascii(.make, "Emulsion"),
            .ascii(.model, "Synthetic"),
            .long(.stripOffsets, [0]),
            .short(.samplesPerPixel, [UInt16(samples)]),
            .long(.rowsPerStrip, [UInt32(height)]),
            .long(.stripByteCounts, [UInt32(stripByteCount)]),
            .bytes(.dngVersion, profile == nil ? Self.dngVersion : Self.gainTableDNGVersion),
            .bytes(.dngBackwardVersion, mosaic.backwardVersion),
            .ascii(.uniqueCameraModel, "Emulsion Synthetic"),
            .long(.blackLevel, Array(repeating: UInt32(Self.blackLevel), count: samples)),
            .long(.whiteLevel, Array(repeating: UInt32(Self.whiteLevel), count: samples)),
            .signedRational(.colorMatrix1, (0..<3).flatMap { row in (0..<3).map { cameraFromXYZ[$0, row] } }),
            .rational(.asShotNeutral, [asShotNeutral.x, asShotNeutral.y, asShotNeutral.z]),
            .signedRational(.baselineExposure, [baselineExposureStops]),
            .short(.calibrationIlluminant1, [Self.d65LightSource]),
        ]
        if mosaic == .bayerRGGB {
            entries += [
                .short(.cfaRepeatPatternDim, [2, 2]),
                .bytes(.cfaPattern, Self.rggbPattern),
            ]
        }
        if let profile {
            entries += [
                .undefined(.profileGainTableMap, Self.gainTableMap(gain: profile.gainTableGain)),
                .float(.profileToneCurve, profile.toneCurve.flatMap { [$0.x, $0.y] }),
                .long(.defaultBlackRender, [Self.defaultBlackRenderNone]),
            ]
        }
        return entries
    }

    private static let uncompressed: UInt16 = 1
    private static let dngVersion: [UInt8] = [1, 4, 0, 0]
    /// ProfileGainTableMap is DNG 1.6.
    private static let gainTableDNGVersion: [UInt8] = [1, 6, 0, 0]
    /// CFAPattern colour indices (0 red, 1 green, 2 blue), row-major.
    private static let rggbPattern: [UInt8] = [0, 1, 1, 2]
    /// DefaultBlackRender 1: no automatic black subtraction, as in iPhone ProRAW.
    private static let defaultBlackRenderNone: UInt32 = 1

    /// ProfileGainTableMap stream in the file's byte order (DNG SDK `dng_gain_table_map::GetStream`):
    /// MapPointsV, MapPointsH (u32); MapSpacingV, MapSpacingH, MapOriginV, MapOriginH (f64);
    /// MapPointsN (u32); five MapInputWeights (f32); then the gains (f32), N innermost.
    private static func gainTableMap(gain: Float) -> [UInt8] {
        let points = 2
        let tablePoints = 2
        let spacing = 1.0
        let origin = 0.0
        // Weights of R, G, B, min and max: any choice gives the same uniform gain.
        let weights: [Float] = [0.25, 0.5, 0.25, 0, 0]
        var bytes = UInt32(points).littleEndianBytes + UInt32(points).littleEndianBytes
        bytes += [spacing, spacing, origin, origin].flatMap(\.bitPattern.littleEndianBytes)
        bytes += UInt32(tablePoints).littleEndianBytes
        bytes += weights.flatMap(\.bitPattern.littleEndianBytes)
        bytes += Array(repeating: gain, count: points * points * tablePoints).flatMap(\.bitPattern.littleEndianBytes)
        return bytes
    }

    /// EXIF LightSource code for D65.
    private static let d65LightSource: UInt16 = 21
}
