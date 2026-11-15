import CoreGraphics
import ImageIO

/// Upright viewfinder frame ↔ sensor-native orientation, for a clockwise rotation in degrees.
enum FrameGeometry {
    static func devicePoint(forFramePoint point: CGPoint, rotationAngle: Double) -> CGPoint {
        switch quarterTurns(rotationAngle) {
        case 1: CGPoint(x: point.y, y: 1 - point.x)
        case 2: CGPoint(x: 1 - point.x, y: 1 - point.y)
        case 3: CGPoint(x: 1 - point.y, y: point.x)
        default: point
        }
    }

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
