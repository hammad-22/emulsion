import CoreImage
import CoreVideo
import simd

/// How video code values are coded (ITU-R BT.2100 Table 9), stated in 10-bit codes.
public enum SignalRange: CaseIterable, Sendable {
    /// Narrow ("video") range: Y′ 64…940, Cb/Cr 64…960 around 512.
    case legal
    /// Full range: Y′ 0…1023, Cb/Cr 0…1023 around 512.
    case full

    var lumaBlack: Double { self == .legal ? 64 : 0 }
    var lumaSpan: Double { self == .legal ? 940 - 64 : 1023 }
    var chromaSpan: Double { self == .legal ? 960 - 64 : 1023 }
    static let chromaCenter = 512.0
}

/// The Y′CbCr → R′G′B′ matrix, by its luma weights (ITU-R BT.709 Table 3, BT.2020 Table 4).
public enum YCbCrMatrix: Sendable {
    case bt709
    /// BT.2020 / BT.2100 non-constant luminance.
    case bt2020

    var weights: (kr: Double, kb: Double) {
        switch self {
        case .bt709: return (0.2126, 0.0722)
        case .bt2020: return (0.2627, 0.0593)
        }
    }

    /// (Y′, Cb, Cr) → R′G′B′, with Cb and Cr centered on 0 (BT.2100 Table 6 inverted).
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

    /// The range from the frame's pixel format and the matrix from its tag, or `fallbackMatrix`
    /// when the tag is missing or not one Emulsion reads.
    init(frame: CVPixelBuffer, layout: YCbCrLayout, fallbackMatrix: YCbCrMatrix) {
        let tag = CVBufferCopyAttachment(frame, kCVImageBufferYCbCrMatrixKey, nil) as? String
        self.init(range: layout.range, matrix: tag.flatMap(YCbCrMatrix.init(tag:)) ?? fallbackMatrix)
    }
}

/// Samples → each curve's formula input, as three affine rows fixed for a whole clip: the signal
/// range, the Y′CbCr matrix and the curve's code-value re-coding folded together, so the kernels
/// do three dot products per pixel. Applied by `samplesToWorking` in the kernel and by `apply`.
struct CurveInputTransform {
    let linear: simd_double3x3
    let offset: SIMD3<Double>

    /// R′G′B′ samples where sample = code × `sampleUnitsPerCode`, coded in `range`.
    init(rgbIn range: SignalRange, sampleUnitsPerCode k: Double, for space: InputColorSpace) {
        let toSignal = simd_double3x3(diagonal: SIMD3(repeating: 1 / (range.lumaSpan * k)))
        self.init(toSignal: toSignal, signalOffset: SIMD3(repeating: -range.lumaBlack / range.lumaSpan), for: space)
    }

    /// (Y′, Cb, Cr) samples where sample = code × `sampleUnitsPerCode`.
    init(ycbcrIn signal: VideoSignal, sampleUnitsPerCode k: Double, for space: InputColorSpace) {
        let r = signal.range
        let scale = simd_double3x3(diagonal: SIMD3(r.lumaSpan * k, r.chromaSpan * k, r.chromaSpan * k)).inverse
        let center = SIMD3(-r.lumaBlack / r.lumaSpan, -SignalRange.chromaCenter / r.chromaSpan, -SignalRange.chromaCenter / r.chromaSpan)
        self.init(toSignal: signal.matrix.toRGB * scale, signalOffset: signal.matrix.toRGB * center, for: space)
    }

    private init(toSignal: simd_double3x3, signalOffset: SIMD3<Double>, for space: InputColorSpace) {
        let (scale, curveOffset) = space.curveInputFromSignal
        linear = toSignal * scale
        offset = signalOffset * scale + curveOffset
    }

    func apply(_ samples: SIMD3<Double>) -> SIMD3<Double> { linear * samples + offset }

    /// The kernel's `r0`, `r1`, `r2` rows.
    var rows: [CIVector] {
        (0..<3).map { CIVector(x: linear[0][$0], y: linear[1][$0], z: linear[2][$0], w: offset[$0]) }
    }
}

/// The 10-bit bi-planar Y′CbCr pixel formats Emulsion reads without conversion.
struct YCbCrLayout {
    let range: SignalRange
    /// 4:2:0 halves chroma vertically as well as horizontally; 4:2:2 only horizontally.
    let chromaRowsHalved: Bool
    /// Samples are 16-bit with the 10-bit code in the high bits (CoreVideo `x420` family).
    static let sampleUnitsPerCode = 64.0 / 65535

    init?(_ frame: CVPixelBuffer) {
        guard CVPixelBufferGetPlaneCount(frame) == 2 else { return nil }
        switch CVPixelBufferGetPixelFormatType(frame) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: (range, chromaRowsHalved) = (.legal, true)
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: (range, chromaRowsHalved) = (.full, true)
        case kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange: (range, chromaRowsHalved) = (.legal, false)
        case kCVPixelFormatType_422YpCbCr10BiPlanarFullRange: (range, chromaRowsHalved) = (.full, false)
        default: return nil
        }
    }

    /// Luma and chroma planes as images on the luma grid, sample values untouched. Chroma is
    /// upsampled bilinearly, co-sited with even luma columns (BT.2020 / H.273 chroma location 0).
    /// Each plane is wrapped without copying; Core Image uploads it when rendering (zero-copy
    /// Metal textures belong with the frame source, MOV-39).
    func planes(of frame: CVPixelBuffer) -> (luma: CIImage, chroma: CIImage)? {
        guard let luma = Self.plane(0, of: frame, format: .L16), let chroma = Self.plane(1, of: frame, format: .RG16) else {
            return nil
        }
        let upsample = CGAffineTransform(translationX: -0.5, y: 0).scaledBy(x: 2, y: chromaRowsHalved ? 2 : 1)
        return (luma, chroma.clampedToExtent().transformed(by: upsample).cropped(to: luma.extent))
    }

    /// The frame stays locked until Core Image releases the plane's data.
    private static func plane(_ index: Int, of frame: CVPixelBuffer, format: CIFormat) -> CIImage? {
        guard CVPixelBufferLockBaseAddress(frame, .readOnly) == kCVReturnSuccess else { return nil }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(frame, index) else {
            CVPixelBufferUnlockBaseAddress(frame, .readOnly)
            return nil
        }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(frame, index)
        let height = CVPixelBufferGetHeightOfPlane(frame, index)
        let data = Data(
            bytesNoCopy: base, count: rowBytes * height,
            deallocator: .custom { _, _ in CVPixelBufferUnlockBaseAddress(frame, .readOnly) })
        let size = CGSize(width: CVPixelBufferGetWidthOfPlane(frame, index), height: height)
        return CIImage(bitmapData: data, bytesPerRow: rowBytes, size: size, format: format, colorSpace: nil)
    }
}
