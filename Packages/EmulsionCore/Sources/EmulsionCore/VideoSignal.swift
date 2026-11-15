import CoreImage
import CoreVideo
import simd

/// How video code values are coded (ITU-R BT.2100 Table 9).
public enum SignalRange: CaseIterable, Sendable {
    /// Narrow ("video") range: Y′ 64…940, Cb/Cr 64…960.
    case legal
    /// Full range: Y′, Cb and Cr 0…1023.
    case full

    var lumaBlack: Double { self == .legal ? 64 : 0 }
    var lumaSpan: Double { self == .legal ? 940 - 64 : 1023 }
    var chromaSpan: Double { self == .legal ? 960 - 64 : 1023 }
    static let chromaCenter = 512.0
    static let largestCode = 1023.0
}

/// The Y′CbCr → R′G′B′ matrix, by its luma weights (BT.709 Table 3, BT.2020 Table 4).
public enum YCbCrMatrix: Sendable {
    case bt709
    case bt2020

    var weights: (kr: Double, kb: Double) {
        switch self {
        case .bt709: return (0.2126, 0.0722)
        case .bt2020: return (0.2627, 0.0593)
        }
    }

    /// (Y′, Cb, Cr) → R′G′B′ with Cb and Cr centred on 0 (BT.2100 Table 6 inverted).
    var toRGB: simd_double3x3 {
        let (kr, kb) = weights
        let kg = 1 - kr - kb
        return simd_double3x3(rows: [
            SIMD3(1, 0, 2 * (1 - kr)),
            SIMD3(1, -2 * (1 - kb) * kb / kg, -2 * (1 - kr) * kr / kg),
            SIMD3(1, 2 * (1 - kb), 0),
        ])
    }

    init?(tag: String) {
        if tag == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String {
            self = .bt709
        } else if tag == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String {
            self = .bt2020
        } else {
            return nil
        }
    }
}

/// How a video frame's Y′CbCr code values are to be read: its range and its matrix.
public struct VideoSignal: Equatable, Sendable {
    public let range: SignalRange
    public let matrix: YCbCrMatrix

    public init(range: SignalRange, matrix: YCbCrMatrix) {
        self.range = range
        self.matrix = matrix
    }

    /// The matrix comes from the frame's tag, else `fallbackMatrix`.
    init(frame: CVPixelBuffer, layout: YCbCrLayout, fallbackMatrix: YCbCrMatrix) {
        let tag = CVBufferCopyAttachment(frame, kCVImageBufferYCbCrMatrixKey, nil) as? String
        self.init(range: layout.range, matrix: tag.flatMap(YCbCrMatrix.init(tag:)) ?? fallbackMatrix)
    }
}
