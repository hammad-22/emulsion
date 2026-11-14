import CoreImage
import CoreVideo

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
