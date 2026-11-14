import CoreGraphics
import Testing

@testable import EmulsionKit

struct FrameGeometryTests {
    private static let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
    private static let center = CGPoint(x: 0.5, y: 0.5)

    /// The upright frame's top-left, top-right, bottom-left and bottom-right corners, and
    /// where each lies on the sensor.
    private static let sensorCorners: [(Double, [CGPoint])] = [
        (0, corners),
        // Portrait: the sensor's top-left is the upright frame's top-right.
        (90, [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)]),
        (180, [CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]),
        (270, [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)]),
    ]

    @Test(arguments: sensorCorners)
    func cornersMapToTheSensor(angle: Double, expected: [CGPoint]) {
        #expect(Self.corners.map { FrameGeometry.devicePoint(forFramePoint: $0, rotationAngle: angle) } == expected)
        #expect(FrameGeometry.devicePoint(forFramePoint: Self.center, rotationAngle: angle) == Self.center)
    }

    @Test func offCentrePointInPortrait() {
        // A tap near the top of a portrait frame is near the sensor's left edge.
        let point = FrameGeometry.devicePoint(forFramePoint: CGPoint(x: 0.5, y: 0.1), rotationAngle: 90)
        #expect(point == CGPoint(x: 0.1, y: 0.5))
    }

    @Test func rotationBecomesTheUprightOrientation() {
        let orientations = [0.0, 90, 180, 270, 360, -90].map(FrameGeometry.orientation(forRotationAngle:))
        #expect(orientations == [.up, .right, .down, .left, .up, .left])
    }
}

struct PhotoDimensionsTests {
    private let iPhone = [PhotoDimensions(width: 4032, height: 3024), PhotoDimensions(width: 8064, height: 6048)]

    @Test func fullIsTheLargestAndStandardIsNearest12MP() {
        let withMiddle = iPhone + [PhotoDimensions(width: 5712, height: 4284)]
        #expect(PhotoDimensions.choose(.full, from: withMiddle) == PhotoDimensions(width: 8064, height: 6048))
        #expect(PhotoDimensions.choose(.standard, from: withMiddle) == PhotoDimensions(width: 4032, height: 3024))
        #expect(PhotoDimensions.supportsFullResolution(withMiddle))
    }

    @Test func oneSizeServesBoth() {
        let only = [PhotoDimensions(width: 4032, height: 3024)]
        #expect(PhotoDimensions.choose(.full, from: only) == only[0])
        #expect(PhotoDimensions.choose(.standard, from: only) == only[0])
        #expect(!PhotoDimensions.supportsFullResolution(only))
    }

    @Test func noSizes() {
        #expect(PhotoDimensions.choose(.standard, from: []) == nil)
        #expect(!PhotoDimensions.supportsFullResolution([]))
    }
}

struct RAWFormatTests {
    @Test func proRAWIsPreferredThenBayer() throws {
        #expect(try RAWFormat.preferred(proRAWAvailable: true, bayerAvailable: true) == .proRAW)
        #expect(try RAWFormat.preferred(proRAWAvailable: false, bayerAvailable: true) == .bayer)
        #expect(throws: CameraError.rawUnsupported) { try RAWFormat.preferred(proRAWAvailable: false, bayerAvailable: false) }
    }
}

struct LensOptionTests {
    @Test func magnificationsReadLikeTheSystemCamera() {
        #expect(LensOption(lens: .ultraWide, magnification: 13.0 / 24).title(isSelected: false) == "0.5")
        #expect(LensOption(lens: .wide, magnification: 1).title(isSelected: true) == "1×")
        #expect(LensOption(lens: .telephoto, magnification: 100.0 / 24).title(isSelected: false) == "4")
        #expect(LensOption(lens: .telephoto, magnification: 2.5).title(isSelected: false) == "2.5")
        #expect(LensOption(lens: .ultraWide, magnification: 0.5).accessibilityLabel == "Ultra Wide, 0.5×")
    }
}
