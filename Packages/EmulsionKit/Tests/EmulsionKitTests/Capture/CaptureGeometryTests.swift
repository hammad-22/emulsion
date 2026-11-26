import CoreGraphics
import Testing

@testable import EmulsionKit

struct FrameGeometryTests {
    private static let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
    private static let center = CGPoint(x: 0.5, y: 0.5)

    /// Where the upright frame's corners (top-left, top-right, bottom-left, bottom-right) lie on the sensor.
    private static let sensorCorners: [(Double, [CGPoint])] = [
        (0, corners),
        (90, [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)]),
        (180, [CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]),
        (270, [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)]),
    ]

    @Test(arguments: sensorCorners)
    func cornersMapToTheSensor(angle: Double, expected: [CGPoint]) {
        #expect(Self.corners.map { FrameGeometry.devicePoint(forFramePoint: $0, rotationAngle: angle) } == expected)
        #expect(FrameGeometry.devicePoint(forFramePoint: Self.center, rotationAngle: angle) == Self.center)
    }

    @Test func aTapNearThePortraitTopIsNearTheSensorsLeftEdge() {
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
    @Test func nativeStopsKeepPhysicalLensesAndUseTheirDisplayedMagnification() {
        let ultraWide = LensOption(lens: .ultraWide, magnification: 13.0 / 24)
        let wide = LensOption(lens: .wide, magnification: 1)
        let telephoto = LensOption(lens: .telephoto, magnification: 100.0 / 24)
        let duplicateWide = LensOption(lens: .ultraWide, magnification: 26.0 / 24, zoomFactor: 2)
        let wideCrop = LensOption(lens: .wide, magnification: 2, zoomFactor: 2)
        let telephotoCrop = LensOption(lens: .telephoto, magnification: 200.0 / 24, zoomFactor: 2)

        let options = LensOption.merging(physical: [ultraWide, wide, telephoto], native: [duplicateWide, wideCrop, telephotoCrop])

        #expect(options == [ultraWide, wide, wideCrop, telephoto, telephotoCrop])
        #expect(options.map(\.displayedMagnification) == [0.5, 1, 2, 4, 8])
        #expect(Set(options.map(\.id)).count == options.count)
    }

    @Test func magnificationsReadLikeTheSystemCamera() {
        #expect(LensOption(lens: .ultraWide, magnification: 13.0 / 24).title(isSelected: false) == "0.5")
        #expect(LensOption(lens: .wide, magnification: 1).title(isSelected: true) == "1×")
        #expect(LensOption(lens: .telephoto, magnification: 100.0 / 24).title(isSelected: false) == "4")
        #expect(LensOption(lens: .telephoto, magnification: 2.5).title(isSelected: false) == "2.5")
        #expect(LensOption(lens: .ultraWide, magnification: 0.5).accessibilityLabel == "Ultra Wide, 0.5×")
    }
}
