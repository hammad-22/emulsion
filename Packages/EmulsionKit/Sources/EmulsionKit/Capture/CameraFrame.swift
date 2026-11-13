import CoreGraphics
import CoreImage
import CoreVideo

/// One viewfinder frame as the camera delivered it, and the clockwise rotation in degrees
/// (0, 90, 180 or 270) that turns it upright for the current interface orientation.
///
/// The rotation travels with the frame instead of being applied by the capture connection:
/// rotating video data output buffers rebuilds the capture pipeline (AVCaptureSession.h,
/// `videoRotationAngle`), which would stall the viewfinder on every interface rotation.
///
/// `@unchecked Sendable` is safe: nothing writes to the pixel buffer after the camera
/// delivers it; it is only read, by Core Image.
public struct CameraFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let rotationAngle: Double

    init(pixelBuffer: CVPixelBuffer, rotationAngle: Double = 0) {
        self.pixelBuffer = pixelBuffer
        self.rotationAngle = rotationAngle
    }

    /// An upright frame drawn on the CPU from `image`, into a BGRA buffer tagged sRGB like a
    /// camera frame tagged with its color space. For the stand-in camera and tests: no GPU
    /// context is made (MOV-127).
    init?(drawing image: CGImage) {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
            let buffer
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: Self.sRGB, bitmapInfo: Self.bgra)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, Self.sRGB, .shouldPropagate)
        self.init(pixelBuffer: buffer)
    }

    /// The frame upright, in the color space its attachments describe.
    var uprightImage: CIImage {
        CIImage(cvPixelBuffer: pixelBuffer).oriented(FrameGeometry.orientation(forRotationAngle: rotationAngle))
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// 32-bit BGRA, premultiplied (opaque here): `kCVPixelFormatType_32BGRA`'s layout.
    static let bgra = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
}
