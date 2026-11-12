import Foundation
import simd

/// A deterministic synthetic DNG (TIFF/EP, little-endian, uncompressed, one strip, 16-bit) that
/// Apple's RAW decoder accepts. Camera values are linear, 1 = sensor white; values outside 0…1
/// clip, as a sensor does. Nothing here models a real camera: the colour matrices are synthetic.
public struct SyntheticDNG: Sendable {
    public enum Mosaic: Sendable, CaseIterable {
        /// One sample per pixel behind an RGGB colour filter array (PhotometricInterpretation 32803).
        case bayerRGGB
        /// Three demosaiced samples per pixel, the container ProRAW uses (PhotometricInterpretation 34892).
        case linearRGB
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
        pixels.reserveCapacity(width * height * samplesPerPixel * 2)
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
                    pixels += [UInt8(code & 0xFF), UInt8(code >> 8)]
                }
            }
        }
        return TIFFWriter.file(entries: entries(stripByteCount: pixels.count), pixels: pixels, minimumSize: Self.minimumFileSize)
    }

    /// ImageIO identifies a TIFF with DNGVersion as DNG only from about 100 KiB (macOS 27.2:
    /// 101,862 bytes read as TIFF, 102,886 as DNG), so tests of Apple's decoder pad to this size.
    private static let minimumFileSize = 128 * 1024

    private var samplesPerPixel: Int { mosaic == .bayerRGGB ? 1 : 3 }

    /// Row-major RGGB: red at even/even, blue at odd/odd.
    private static func rggbChannel(x: Int, y: Int) -> Int { (x % 2) + (y % 2) }

    /// CIRAWFilter needs NewSubFileType, PhotometricInterpretation, StripByteCounts, DNGVersion,
    /// ColorMatrix1, SamplesPerPixel, AsShotNeutral, BaselineExposure and the CFA pattern (macOS 27.2).
    private func entries(stripByteCount: Int) -> [TIFFEntry] {
        let samples = samplesPerPixel
        var entries: [TIFFEntry] = [
            .long(.newSubFileType, [0]),
            .long(.imageWidth, [UInt32(width)]),
            .long(.imageLength, [UInt32(height)]),
            .short(.bitsPerSample, Array(repeating: 16, count: samples)),
            .short(.compression, [1]),
            .short(.photometricInterpretation, [mosaic == .bayerRGGB ? 32803 : 34892]),
            .ascii(.make, "Emulsion"),
            .ascii(.model, "Synthetic"),
            .long(.stripOffsets, [0]),
            .short(.samplesPerPixel, [UInt16(samples)]),
            .long(.rowsPerStrip, [UInt32(height)]),
            .long(.stripByteCounts, [UInt32(stripByteCount)]),
            // ProfileGainTableMap is DNG 1.6.
            .bytes(.dngVersion, profile == nil ? [1, 4, 0, 0] : [1, 6, 0, 0]),
            .bytes(.dngBackwardVersion, mosaic == .bayerRGGB ? [1, 1, 0, 0] : [1, 3, 0, 0]),
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
                .bytes(.cfaPattern, [0, 1, 1, 2]),
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

// MARK: Synthetic cameras and illuminants

extension SyntheticDNG {
    /// A typical daylight sensor neutral: red and blue sites see less of a D65 white than green.
    static let daylightNeutral = SIMD3<Double>(0.48, 1.0, 0.62)

    /// Linear sRGB (D65) → XYZ, IEC 61966-2-1 primaries.
    public static let xyzFromLinearSRGB = simd_double3x3(rows: [
        SIMD3(0.4124564, 0.3575761, 0.1804375),
        SIMD3(0.2126729, 0.7151522, 0.0721750),
        SIMD3(0.0193339, 0.1191920, 0.9503041),
    ])

    /// Linear Rec. 2020 (D65) → XYZ, ITU-R BT.2020 primaries.
    private static let xyzFromLinearRec2020 = simd_double3x3(rows: [
        SIMD3(0.6369580, 0.1446169, 0.1688810),
        SIMD3(0.2627002, 0.6779981, 0.0593017),
        SIMD3(0.0000000, 0.0280727, 1.0609851),
    ])

    /// Artistic stand-in for overlapping sensor dye responses; rows sum to 1 so white stays white.
    private static let sensorCrosstalk = simd_double3x3(rows: [
        SIMD3(0.90, 0.08, 0.02),
        SIMD3(0.05, 0.90, 0.05),
        SIMD3(0.02, 0.10, 0.88),
    ])

    /// `diag(daylightNeutral) · XYZ→linear sRGB`: a scene colour `c` in linear sRGB under D65
    /// reads `daylightNeutral * c` exactly in camera space. Its gamut is sRGB, so it cannot
    /// record colours outside sRGB (they clip to 0 at the sensor).
    public static let sRGBCameraFromXYZ = simd_double3x3(diagonal: daylightNeutral) * xyzFromLinearSRGB.inverse

    /// A wider, non-trivial synthetic camera: `diag(daylightNeutral) · crosstalk · XYZ→linear Rec. 2020`.
    /// D65 white still reads `daylightNeutral`; Display P3 colours outside sRGB stay positive,
    /// so they survive the sensor.
    static let wideGamutCameraFromXYZ = simd_double3x3(diagonal: daylightNeutral) * sensorCrosstalk * xyzFromLinearRec2020.inverse

    /// Camera value of a scene colour given in linear sRGB (D65 light).
    public static func camera(linearSRGB: SIMD3<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        cameraFromXYZ * (xyzFromLinearSRGB * linearSRGB)
    }

    /// Camera value of a light of chromaticity `xy` and luminance (Y) 1.
    public static func camera(chromaticity xy: SIMD2<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        cameraFromXYZ * SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y)
    }

    /// Camera neutral (green = 1) of a light of chromaticity `xy`, as DNG AsShotNeutral stores it.
    public static func neutral(chromaticity xy: SIMD2<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        let value = camera(chromaticity: xy, cameraFromXYZ: cameraFromXYZ)
        return value / value.y
    }

    /// CIE 1931 xy of a Planckian radiator, 1667–25000 K: the Kim et al. 2002 cubic-spline
    /// approximation of the Planckian locus.
    public static func planckianChromaticity(kelvin t: Double) -> SIMD2<Double> {
        let t3 = t * t * t
        let x =
            t <= 4000
            ? -0.2661239e9 / t3 - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
            : -3.0258469e9 / t3 + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
        let y: Double
        if t <= 2222 {
            y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else if t <= 4000 {
            y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        } else {
            y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
        }
        return SIMD2(x, y)
    }

    /// D65 white point as the colour standards round it (sRGB, Rec. 709/2020, Display P3), the
    /// value `InputColorSpace.d65` uses.
    public static let d65Chromaticity = SIMD2<Double>(0.3127, 0.3290)
}

// MARK: TIFF encoding

private enum TIFFTag: UInt16 {
    case newSubFileType = 254
    case imageWidth = 256
    case imageLength = 257
    case bitsPerSample = 258
    case compression = 259
    case photometricInterpretation = 262
    case make = 271
    case model = 272
    case stripOffsets = 273
    case samplesPerPixel = 277
    case rowsPerStrip = 278
    case stripByteCounts = 279
    case cfaRepeatPatternDim = 33421
    case cfaPattern = 33422
    case dngVersion = 50706
    case dngBackwardVersion = 50707
    case uniqueCameraModel = 50708
    case blackLevel = 50714
    case whiteLevel = 50717
    case colorMatrix1 = 50721
    case asShotNeutral = 50728
    case baselineExposure = 50730
    case calibrationIlluminant1 = 50778
    case profileToneCurve = 50940
    case defaultBlackRender = 51110
    case profileGainTableMap = 52525
}

private struct TIFFEntry {
    let tag: TIFFTag
    let type: UInt16
    let count: Int
    let payload: [UInt8]

    /// Denominator for (signed) rationals: six decimal places.
    private static let rationalDenominator = 1_000_000

    static func bytes(_ tag: TIFFTag, _ values: [UInt8]) -> TIFFEntry { TIFFEntry(tag: tag, type: 1, count: values.count, payload: values) }
    static func ascii(_ tag: TIFFTag, _ text: String) -> TIFFEntry {
        let bytes = Array(text.utf8) + [0]
        return TIFFEntry(tag: tag, type: 2, count: bytes.count, payload: bytes)
    }
    static func short(_ tag: TIFFTag, _ values: [UInt16]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: 3, count: values.count, payload: values.flatMap(\.littleEndianBytes))
    }
    static func long(_ tag: TIFFTag, _ values: [UInt32]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: 4, count: values.count, payload: values.flatMap(\.littleEndianBytes))
    }
    static func undefined(_ tag: TIFFTag, _ values: [UInt8]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: 7, count: values.count, payload: values)
    }
    static func float(_ tag: TIFFTag, _ values: [Float]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: 11, count: values.count, payload: values.flatMap(\.bitPattern.littleEndianBytes))
    }
    static func rational(_ tag: TIFFTag, _ values: [Double]) -> TIFFEntry {
        let words = values.flatMap { [UInt32(($0 * Double(rationalDenominator)).rounded()), UInt32(rationalDenominator)] }
        return TIFFEntry(tag: tag, type: 5, count: values.count, payload: words.flatMap(\.littleEndianBytes))
    }
    static func signedRational(_ tag: TIFFTag, _ values: [Double]) -> TIFFEntry {
        let words = values.flatMap { [Int32(($0 * Double(rationalDenominator)).rounded()), Int32(rationalDenominator)] }
        return TIFFEntry(tag: tag, type: 10, count: values.count, payload: words.flatMap(\.littleEndianBytes))
    }
}

/// Little-endian TIFF with one IFD: header, IFD, out-of-line values, the single strip, then zero
/// padding up to `minimumSize`. StripOffsets is filled in.
private enum TIFFWriter {
    private static let headerSize = 8
    private static let entrySize = 12
    private static let inlineCapacity = 4

    static func file(entries: [TIFFEntry], pixels: [UInt8], minimumSize: Int) -> Data {
        let sorted = entries.sorted { $0.tag.rawValue < $1.tag.rawValue }
        let overflowStart = headerSize + 2 + sorted.count * entrySize + 4
        let overflowSize = sorted.reduce(0) { $0 + ($1.payload.count > inlineCapacity ? padded($1.payload.count) : 0) }
        let pixelOffset = overflowStart + overflowSize

        var out: [UInt8] = Array("II".utf8) + UInt16(42).littleEndianBytes + UInt32(headerSize).littleEndianBytes
        var overflow = [UInt8]()
        out += UInt16(sorted.count).littleEndianBytes
        for entry in sorted {
            let payload = entry.tag == .stripOffsets ? UInt32(pixelOffset).littleEndianBytes : entry.payload
            out += entry.tag.rawValue.littleEndianBytes + entry.type.littleEndianBytes + UInt32(entry.count).littleEndianBytes
            if payload.count <= inlineCapacity {
                out += payload + Array(repeating: 0, count: inlineCapacity - payload.count)
            } else {
                out += UInt32(overflowStart + overflow.count).littleEndianBytes
                overflow += payload + Array(repeating: 0, count: padded(payload.count) - payload.count)
            }
        }
        out += UInt32(0).littleEndianBytes + overflow + pixels
        return Data(out + Array(repeating: 0, count: max(0, minimumSize - out.count)))
    }

    /// TIFF offsets must be word aligned.
    private static func padded(_ count: Int) -> Int { (count + 1) / 2 * 2 }
}

extension FixedWidthInteger {
    fileprivate var littleEndianBytes: [UInt8] { withUnsafeBytes(of: littleEndian) { Array($0) } }
}
