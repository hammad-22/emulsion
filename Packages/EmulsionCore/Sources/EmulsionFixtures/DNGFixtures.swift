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

    public var mosaic: Mosaic
    /// Pixels; even, so the RGGB pattern tiles the image.
    public var width: Int
    public var height: Int
    public var baselineExposureStops: Double
    /// Camera-space neutral (green = 1), DNG AsShotNeutral.
    public var asShotNeutral: SIMD3<Double>
    /// XYZ → camera, DNG ColorMatrix1 for CalibrationIlluminant1 = D65.
    public var cameraFromXYZ: simd_double3x3
    public var blackLevel: Int
    public var whiteLevel: Int

    public init(
        mosaic: Mosaic, width: Int, height: Int, baselineExposureStops: Double = 0,
        asShotNeutral: SIMD3<Double> = SyntheticDNG.daylightNeutral,
        cameraFromXYZ: simd_double3x3 = SyntheticDNG.cameraFromXYZ(),
        blackLevel: Int = 0, whiteLevel: Int = 65535
    ) {
        precondition(width > 0 && height > 0 && width.isMultiple(of: 2) && height.isMultiple(of: 2), "DNG size must be even")
        self.mosaic = mosaic
        self.width = width
        self.height = height
        self.baselineExposureStops = baselineExposureStops
        self.asShotNeutral = asShotNeutral
        self.cameraFromXYZ = cameraFromXYZ
        self.blackLevel = blackLevel
        self.whiteLevel = whiteLevel
    }

    /// The file. `camera(x, y)` gives the camera-space linear value of a pixel, y = 0 the top row.
    /// Files shorter than `minimumSize` are padded with trailing zeros.
    public func data(minimumSize: Int = Self.minimumFileSize, _ camera: (Int, Int) -> SIMD3<Double>) -> Data {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * samplesPerPixel * 2)
        let span = Double(whiteLevel - blackLevel)
        for y in 0..<height {
            for x in 0..<width {
                let value = camera(x, y)
                let samples: [Double] =
                    switch mosaic {
                    case .bayerRGGB: [value[Self.rggbChannel(x: x, y: y)]]
                    case .linearRGB: [value.x, value.y, value.z]
                    }
                for sample in samples {
                    let code = UInt16(Double(blackLevel) + (min(max(sample, 0), 1) * span).rounded())
                    pixels += [UInt8(code & 0xFF), UInt8(code >> 8)]
                }
            }
        }
        return TIFFWriter.file(entries: entries(stripByteCount: pixels.count), pixels: pixels, minimumSize: minimumSize)
    }

    /// ImageIO identifies a TIFF with DNGVersion as DNG only from about 100 KiB (macOS 27.2:
    /// 101,862 bytes read as TIFF, 102,886 as DNG), so tests of Apple's decoder pad to this size.
    public static let minimumFileSize = 128 * 1024

    private var samplesPerPixel: Int { mosaic == .bayerRGGB ? 1 : 3 }

    /// Row-major RGGB: red at even/even, blue at odd/odd.
    private static func rggbChannel(x: Int, y: Int) -> Int { (x % 2) + (y % 2) }

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
            .short(.orientation, [1]),
            .short(.samplesPerPixel, [UInt16(samples)]),
            .long(.rowsPerStrip, [UInt32(height)]),
            .long(.stripByteCounts, [UInt32(stripByteCount)]),
            .short(.planarConfiguration, [1]),
            .bytes(.dngVersion, [1, 4, 0, 0]),
            .bytes(.dngBackwardVersion, mosaic == .bayerRGGB ? [1, 1, 0, 0] : [1, 3, 0, 0]),
            .ascii(.uniqueCameraModel, "Emulsion Synthetic"),
            .long(.blackLevel, Array(repeating: UInt32(blackLevel), count: samples)),
            .long(.whiteLevel, Array(repeating: UInt32(whiteLevel), count: samples)),
            .long(.defaultCropOrigin, [0, 0]),
            .long(.defaultCropSize, [UInt32(width), UInt32(height)]),
            .signedRational(.colorMatrix1, (0..<3).flatMap { row in (0..<3).map { cameraFromXYZ[$0, row] } }),
            .rational(.analogBalance, [1, 1, 1]),
            .rational(.asShotNeutral, [asShotNeutral.x, asShotNeutral.y, asShotNeutral.z]),
            .signedRational(.baselineExposure, [baselineExposureStops]),
            .short(.calibrationIlluminant1, [Self.d65LightSource]),
            .long(.activeArea, [0, 0, UInt32(height), UInt32(width)]),
        ]
        if mosaic == .bayerRGGB {
            entries += [
                .short(.cfaRepeatPatternDim, [2, 2]),
                .bytes(.cfaPattern, [0, 1, 1, 2]),
                .bytes(.cfaPlaneColor, [0, 1, 2]),
                .short(.cfaLayout, [1]),
            ]
        }
        return entries
    }

    /// EXIF LightSource code for D65.
    private static let d65LightSource: UInt16 = 21
}

// MARK: Synthetic cameras and illuminants

extension SyntheticDNG {
    /// A typical daylight sensor neutral: red and blue sites see less of a D65 white than green.
    public static let daylightNeutral = SIMD3<Double>(0.48, 1.0, 0.62)

    /// Linear sRGB (D65) → XYZ, IEC 61966-2-1 primaries.
    public static let xyzFromLinearSRGB = simd_double3x3(rows: [
        SIMD3(0.4124564, 0.3575761, 0.1804375),
        SIMD3(0.2126729, 0.7151522, 0.0721750),
        SIMD3(0.0193339, 0.1191920, 0.9503041),
    ])

    /// Linear Rec. 2020 (D65) → XYZ, ITU-R BT.2020 primaries.
    static let xyzFromLinearRec2020 = simd_double3x3(rows: [
        SIMD3(0.6369580, 0.1446169, 0.1688810),
        SIMD3(0.2627002, 0.6779981, 0.0593017),
        SIMD3(0.0000000, 0.0280727, 1.0609851),
    ])

    /// Artistic stand-in for overlapping sensor dye responses; rows sum to 1 so white stays white.
    static let sensorCrosstalk = simd_double3x3(rows: [
        SIMD3(0.90, 0.08, 0.02),
        SIMD3(0.05, 0.90, 0.05),
        SIMD3(0.02, 0.10, 0.88),
    ])

    /// `diag(neutral) · XYZ→linear sRGB`: a scene colour `c` in linear sRGB under D65 reads
    /// `neutral * c` exactly in camera space. Its gamut is sRGB, so it cannot record colours
    /// outside sRGB (they clip to 0 at the sensor).
    public static func cameraFromXYZ(neutral: SIMD3<Double> = daylightNeutral) -> simd_double3x3 {
        simd_double3x3(diagonal: neutral) * xyzFromLinearSRGB.inverse
    }

    /// A wider, non-trivial synthetic camera: `diag(neutral) · crosstalk · XYZ→linear Rec. 2020`.
    /// D65 white still reads `neutral`; Display P3 colours outside sRGB stay positive, so they
    /// survive the sensor.
    public static func wideGamutCameraFromXYZ(neutral: SIMD3<Double> = daylightNeutral) -> simd_double3x3 {
        simd_double3x3(diagonal: neutral) * sensorCrosstalk * xyzFromLinearRec2020.inverse
    }

    /// Camera value of a scene colour given in linear sRGB (D65 light).
    public static func camera(linearSRGB: SIMD3<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        cameraFromXYZ * (xyzFromLinearSRGB * linearSRGB)
    }

    /// Camera value of a light of chromaticity `xy` and luminance `luminance` (Y).
    public static func camera(chromaticity xy: SIMD2<Double>, luminance: Double = 1, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        cameraFromXYZ * (luminance * SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y))
    }

    /// Camera neutral (green = 1) of a light of chromaticity `xy`, as DNG AsShotNeutral stores it.
    public static func neutral(chromaticity xy: SIMD2<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        let value = camera(chromaticity: xy, cameraFromXYZ: cameraFromXYZ)
        return value / value.y
    }

    /// CIE 1931 xy of a Planckian radiator, Kim et al. 2002 cubic spline (US patent 7,024,034), 1667–25000 K.
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

    /// CIE 1931 xy of CIE daylight (D series) at correlated colour temperature `t`, CIE 15:2004
    /// eq. 3.3–3.4. Defined for 4000–25000 K only.
    public static func daylightChromaticity(kelvin t: Double) -> SIMD2<Double>? {
        guard (4000...25000).contains(t) else { return nil }
        let t3 = t * t * t
        let x =
            t <= 7000
            ? -4.6070e9 / t3 + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
            : -2.0064e9 / t3 + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
        return SIMD2(x, -3.000 * x * x + 2.870 * x - 0.275)
    }

    /// D65 white point, CIE 15:2004 table T.3 (2°).
    public static let d65Chromaticity = SIMD2<Double>(0.31271, 0.32902)
}

// MARK: Patch charts

/// A grid of flat patches, `cell` pixels square, row-major from the top-left. Cells are large
/// enough that demosaic and denoise edges leave each centre untouched.
public struct PatchChart: Sendable {
    public static let minimumCell = 32

    public let patches: [SIMD3<Double>]
    public let cell: Int
    public let columns: Int

    public init(_ patches: [SIMD3<Double>], cell: Int = 48, columns: Int = 8) {
        precondition(cell >= Self.minimumCell && cell.isMultiple(of: 2), "cells must be even and at least \(Self.minimumCell) px")
        self.patches = patches
        self.cell = cell
        self.columns = min(columns, patches.count)
    }

    public var rows: Int { (patches.count + columns - 1) / columns }
    public var width: Int { columns * cell }
    public var height: Int { rows * cell }

    /// The patch under pixel (x, y), y = 0 the top row; black outside the patches.
    public func value(x: Int, y: Int) -> SIMD3<Double> {
        let index = (y / cell) * columns + x / cell
        return index < patches.count ? patches[index] : .zero
    }

    /// The central quarter (half width, half height) of patch `index` in top-left pixel
    /// coordinates, for an image drawn at `scale` times the chart size.
    public func centre(of index: Int, scale: Double = 1) -> (x: Range<Int>, y: Range<Int>) {
        let size = Double(cell) * scale
        let left = Double(index % columns) * size
        let top = Double(index / columns) * size
        let lower = { (origin: Double) in Int((origin + size / 4).rounded()) }
        let upper = { (origin: Double) in max(lower(origin) + 1, Int((origin + 3 * size / 4).rounded())) }
        return (lower(left)..<upper(left), lower(top)..<upper(top))
    }

    /// Mean of each patch's central quarter in `pixels` (bottom row first, as `Fixtures.linear`
    /// returns them) of an image `width` × `height` drawn from this chart at any scale.
    public func means(of pixels: [SIMD3<Double>], width: Int, height: Int) -> [SIMD3<Double>] {
        let scale = Double(width) / Double(self.width)
        return patches.indices.map { index in
            let (xs, ys) = centre(of: index, scale: scale)
            var sum = SIMD3<Double>.zero
            for y in ys { for x in xs { sum += pixels[(height - 1 - y) * width + x] } }
            return sum / Double(xs.count * ys.count)
        }
    }
}

// MARK: Develop charts

/// The scene and synthetic files used to measure RAW develop (MOV-79): a half-stop neutral
/// wedge around mid-gray followed by chromatic patches, two of them outside sRGB.
public enum RAWDevelopChart {
    /// Linear Display P3 → linear sRGB (both D65).
    public static let linearSRGBFromP3 =
        SyntheticDNG.xyzFromLinearSRGB.inverse
        * simd_double3x3(rows: [
            SIMD3(0.4865709, 0.2656677, 0.1982173),
            SIMD3(0.2289746, 0.6917385, 0.0792869),
            SIMD3(0.0000000, 0.0451134, 1.0439444),
        ])

    public static let midGray = 0.18
    /// With the default camera the top three patches clip green at the sensor, and +3.5 also clips blue.
    public static let wedgeStops = Array(stride(from: -4.0, through: 3.5, by: 0.5))
    /// Display P3 colours with a negative linear sRGB component: P3 red at 0.9 (G −0.038,
    /// B −0.018 in sRGB) and a saturated green (R −0.118).
    public static let outOfSRGBP3: [SIMD3<Double>] = [[0.9, 0, 0], [0.05, 0.8, 0.1]]
    /// Linear sRGB: the six chromatic `SceneFixtures.patchesP3`, then `outOfSRGBP3`.
    public static let chromaticScene: [SIMD3<Double>] =
        SceneFixtures.patchesP3.prefix(6).map { linearSRGBFromP3 * SIMD3<Double>($0) }
        + outOfSRGBP3.map { linearSRGBFromP3 * $0 }
    public static let neutralScene = wedgeStops.map { SIMD3(repeating: midGray * pow(2, $0)) }
    /// Linear sRGB scene: the neutral wedge, then the chromatic patches.
    public static let scene = neutralScene + chromaticScene
    public static let neutralIndices = neutralScene.indices
    public static let chromaticIndices = neutralScene.count..<scene.count
    public static let outOfSRGBIndices = (scene.count - outOfSRGBP3.count)..<scene.count
    /// Display P3 colours outside sRGB survive this camera's sensor.
    public static let camera = SyntheticDNG.wideGamutCameraFromXYZ()

    public static func chart(cell: Int = 48, columns: Int = 8) -> PatchChart { PatchChart(scene, cell: cell, columns: columns) }

    public static func cameraValues(_ scene: [SIMD3<Double>], cameraFromXYZ: simd_double3x3 = camera) -> [SIMD3<Double>] {
        scene.map { SyntheticDNG.camera(linearSRGB: $0, cameraFromXYZ: cameraFromXYZ) }
    }

    /// A DNG of `chart` (scene values in linear sRGB) as `cameraFromXYZ` records it.
    public static func dng(
        _ mosaic: SyntheticDNG.Mosaic, chart: PatchChart, baselineStops: Double = 0,
        neutral: SIMD3<Double> = SyntheticDNG.daylightNeutral, cameraFromXYZ: simd_double3x3 = camera,
        minimumSize: Int = SyntheticDNG.minimumFileSize
    ) -> Data {
        let sensor = PatchChart(cameraValues(chart.patches, cameraFromXYZ: cameraFromXYZ), cell: chart.cell, columns: chart.columns)
        return SyntheticDNG(
            mosaic: mosaic, width: chart.width, height: chart.height, baselineExposureStops: baselineStops,
            asShotNeutral: neutral, cameraFromXYZ: cameraFromXYZ
        ).data(minimumSize: minimumSize) { sensor.value(x: $0, y: $1) }
    }
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
    case orientation = 274
    case samplesPerPixel = 277
    case rowsPerStrip = 278
    case stripByteCounts = 279
    case planarConfiguration = 284
    case cfaRepeatPatternDim = 33421
    case cfaPattern = 33422
    case dngVersion = 50706
    case dngBackwardVersion = 50707
    case uniqueCameraModel = 50708
    case cfaPlaneColor = 50710
    case cfaLayout = 50711
    case blackLevel = 50714
    case whiteLevel = 50717
    case defaultCropOrigin = 50719
    case defaultCropSize = 50720
    case colorMatrix1 = 50721
    case analogBalance = 50727
    case asShotNeutral = 50728
    case baselineExposure = 50730
    case calibrationIlluminant1 = 50778
    case activeArea = 50829
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
