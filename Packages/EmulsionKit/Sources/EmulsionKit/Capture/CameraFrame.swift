import CoreGraphics
import CoreImage
import CoreVideo

/// A frame and the clockwise rotation that turns it upright. See Packages/EmulsionKit/NOTES.md, "CameraFrame".
/// `@unchecked Sendable` is safe: nothing writes to the pixel buffer after the camera delivers it.
public struct CameraFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let rotationAngle: Double

    init(pixelBuffer: CVPixelBuffer, rotationAngle: Double = 0) {
        self.pixelBuffer = pixelBuffer
        self.rotationAngle = rotationAngle
    }

    /// Drawn on the CPU, so no GPU context is made (MOV-127).
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
    /// `kCVPixelFormatType_32BGRA`'s layout, premultiplied (opaque here).
    static let bgra = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
}
