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

    public init(pixelBuffer: CVPixelBuffer, rotationAngle: Double = 0) {
        self.pixelBuffer = pixelBuffer
        self.rotationAngle = rotationAngle
    }

    /// The frame upright, in the color space its attachments describe.
    var uprightImage: CIImage {
        CIImage(cvPixelBuffer: pixelBuffer).oriented(FrameGeometry.orientation(forRotationAngle: rotationAngle))
    }
}
