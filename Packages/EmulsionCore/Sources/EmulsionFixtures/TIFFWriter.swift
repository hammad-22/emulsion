import Foundation

/// The TIFF and DNG tags `SyntheticDNG` writes (TIFF 6.0, TIFF/EP, DNG 1.6).
enum TIFFTag: UInt16 {
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

/// TIFF 6.0 field types.
enum TIFFFieldType: UInt16 {
    case byte = 1
    case ascii = 2
    case short = 3
    case long = 4
    case rational = 5
    case undefined = 7
    case signedRational = 10
    case float = 11
}

struct TIFFEntry {
    let tag: TIFFTag
    let type: TIFFFieldType
    let count: Int
    let payload: [UInt8]

    /// Denominator for (signed) rationals: six decimal places.
    private static let rationalDenominator = 1_000_000

    static func bytes(_ tag: TIFFTag, _ values: [UInt8]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: .byte, count: values.count, payload: values)
    }
    static func ascii(_ tag: TIFFTag, _ text: String) -> TIFFEntry {
        let bytes = Array(text.utf8) + [0]
        return TIFFEntry(tag: tag, type: .ascii, count: bytes.count, payload: bytes)
    }
    static func short(_ tag: TIFFTag, _ values: [UInt16]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: .short, count: values.count, payload: values.flatMap(\.littleEndianBytes))
    }
    static func long(_ tag: TIFFTag, _ values: [UInt32]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: .long, count: values.count, payload: values.flatMap(\.littleEndianBytes))
    }
    static func undefined(_ tag: TIFFTag, _ values: [UInt8]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: .undefined, count: values.count, payload: values)
    }
    static func float(_ tag: TIFFTag, _ values: [Float]) -> TIFFEntry {
        TIFFEntry(tag: tag, type: .float, count: values.count, payload: values.flatMap(\.bitPattern.littleEndianBytes))
    }
    static func rational(_ tag: TIFFTag, _ values: [Double]) -> TIFFEntry {
        let words = values.flatMap { [UInt32(($0 * Double(rationalDenominator)).rounded()), UInt32(rationalDenominator)] }
        return TIFFEntry(tag: tag, type: .rational, count: values.count, payload: words.flatMap(\.littleEndianBytes))
    }
    static func signedRational(_ tag: TIFFTag, _ values: [Double]) -> TIFFEntry {
        let words = values.flatMap { [Int32(($0 * Double(rationalDenominator)).rounded()), Int32(rationalDenominator)] }
        return TIFFEntry(tag: tag, type: .signedRational, count: values.count, payload: words.flatMap(\.littleEndianBytes))
    }
}

/// Little-endian TIFF with one IFD: header, IFD, out-of-line values, the single strip, then zero
/// padding up to `minimumSize`. StripOffsets is filled in.
enum TIFFWriter {
    private static let littleEndianMarker = "II"
    private static let magicNumber: UInt16 = 42
    private static let headerSize = 8
    private static let entryCountSize = 2
    private static let entrySize = 12
    private static let nextIFDOffsetSize = 4
    private static let inlineCapacity = 4

    static func file(entries: [TIFFEntry], pixels: [UInt8], minimumSize: Int) -> Data {
        let sorted = entries.sorted { $0.tag.rawValue < $1.tag.rawValue }
        let overflowStart = headerSize + entryCountSize + sorted.count * entrySize + nextIFDOffsetSize
        let overflowSize = sorted.reduce(0) { $0 + ($1.payload.count > inlineCapacity ? padded($1.payload.count) : 0) }
        let pixelOffset = overflowStart + overflowSize

        var out: [UInt8] = Array(littleEndianMarker.utf8) + magicNumber.littleEndianBytes + UInt32(headerSize).littleEndianBytes
        var overflow = [UInt8]()
        out += UInt16(sorted.count).littleEndianBytes
        for entry in sorted {
            let payload = entry.tag == .stripOffsets ? UInt32(pixelOffset).littleEndianBytes : entry.payload
            out += entry.tag.rawValue.littleEndianBytes + entry.type.rawValue.littleEndianBytes + UInt32(entry.count).littleEndianBytes
            if payload.count <= inlineCapacity {
                out += payload + Array(repeating: 0, count: inlineCapacity - payload.count)
            } else {
                out += UInt32(overflowStart + overflow.count).littleEndianBytes
                overflow += payload + Array(repeating: 0, count: padded(payload.count) - payload.count)
            }
        }
        let noNextIFD = UInt32(0)
        out += noNextIFD.littleEndianBytes + overflow + pixels
        return Data(out + Array(repeating: 0, count: max(0, minimumSize - out.count)))
    }

    /// TIFF offsets must be word aligned.
    private static func padded(_ count: Int) -> Int { (count + 1) / 2 * 2 }
}

extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] { withUnsafeBytes(of: littleEndian) { Array($0) } }
}
