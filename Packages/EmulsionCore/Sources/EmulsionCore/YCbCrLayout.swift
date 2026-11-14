import CoreImage
import CoreVideo

/// The 10-bit bi-planar Y′CbCr formats read without conversion (docs/CONSTANTS.md).
struct YCbCrLayout {
    let range: SignalRange
    let chromaRowsHalved: Bool
    /// 10-bit codes in the high bits of 16-bit samples (CoreVideo `x420` family).
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

    /// Planes on the luma grid; chroma co-sited with even luma columns (H.273 chroma location 0).
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
