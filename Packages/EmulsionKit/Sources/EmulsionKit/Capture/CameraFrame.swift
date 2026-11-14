import CoreGraphics
import CoreImage
import CoreVideo

/// One viewfinder frame and the clockwise rotation in degrees that turns it upright. The rotation
/// travels with the frame because rotating output buffers rebuilds the capture pipeline
/// (AVCaptureSession.h, `videoRotationAngle`), stalling the viewfinder on every rotation.
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

    /// Drawn on the CPU, into a BGRA buffer tagged sRGB, so no GPU context is made (MOV-127).
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

    var uprightImage: CIImage {
        CIImage(cvPixelBuffer: pixelBuffer).oriented(FrameGeometry.orientation(forRotationAngle: rotationAngle))
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// 32-bit BGRA, premultiplied (opaque here): `kCVPixelFormatType_32BGRA`'s layout.
    static let bgra = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
}
