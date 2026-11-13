import CoreGraphics
import ImageIO

/// Converts between the upright frame the viewfinder shows and the camera sensor's native
/// landscape orientation, given the clockwise rotation (0, 90, 180, 270) between them.
enum FrameGeometry {
    /// A point of interest for `AVCaptureDevice` (sensor-native, (0,0) top-left, (1,1)
    /// bottom-right per `focusPointOfInterest`) from a normalized point in the upright frame.
    static func devicePoint(forFramePoint point: CGPoint, rotationAngle: Double) -> CGPoint {
        switch quarterTurns(rotationAngle) {
        case 1: CGPoint(x: point.y, y: 1 - point.x)
        case 2: CGPoint(x: 1 - point.x, y: 1 - point.y)
        case 3: CGPoint(x: 1 - point.y, y: point.x)
        default: point
        }
    }

    /// The orientation that displays a sensor-native image upright after rotating it
    /// clockwise by `rotationAngle`.
    static func orientation(forRotationAngle rotationAngle: Double) -> CGImagePropertyOrientation {
        switch quarterTurns(rotationAngle) {
        case 1: .right
        case 2: .down
        case 3: .left
        default: .up
        }
    }

    private static func quarterTurns(_ angle: Double) -> Int {
        let turns = Int((angle / 90).rounded()) % 4
        return turns < 0 ? turns + 4 : turns
    }
}
