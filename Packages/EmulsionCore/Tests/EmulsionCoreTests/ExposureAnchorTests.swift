import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// The exposure anchor's maths (MOV-134), on pixel arrays.
struct ExposureAnchorTests {
    /// Chromatic and neutral linear sRGB pixels from deep shadow to above 1, one with a negative channel.
    static let linear: [SIMD4<Float>] = [
        SIMD4(0.01, 0.01, 0.01, 1), SIMD4(0.045, 0.03, 0.02, 1), SIMD4(0.02, 0.06, 0.03, 1), SIMD4(0.05, 0.04, 0.09, 1),
        SIMD4(0.3, 0.2, 0.1, 1), SIMD4(0.8, -0.02, 0.05, 1), SIMD4(1.6, 1.4, 1.2, 1), SIMD4(0.25, 0.25, 0.25, 1),
    ]
    /// Pure arithmetic in Double from Float inputs.
    static let arithmeticTolerance = 1e-9

    static func scaled(_ pixels: [SIMD4<Float>], by gain: Float) -> [SIMD4<Float>] { pixels.map { $0 * gain } }

    @Test func uniformGainGivesItsStops() {
        let anchor = ExposureAnchor.stops(linear: Self.linear, profile: Self.scaled(Self.linear, by: 4))
        #expect(abs(anchor - 2) < Self.arithmeticTolerance, "anchor \(anchor)")
    }

    @Test func pixelsOutsideTheWindowDontCount() {
        // Rendered at mid-gray with a ×4 gain, against bright pixels (Y ≈ 2) with a ×0.5 gain.
        let inWindow = [SIMD4<Float>](repeating: SIMD4(0.045, 0.045, 0.045, 1), count: 10)
        let outside = [SIMD4<Float>](repeating: SIMD4(4, 4, 4, 1), count: 90)
        let anchor = ExposureAnchor.stops(
            linear: inWindow + outside, profile: Self.scaled(inWindow, by: 4) + Self.scaled(outside, by: 0.5))
        #expect(abs(anchor - 2) < Self.arithmeticTolerance, "anchor \(anchor)")
    }

    @Test func fewWindowPixelsFallBackToAllPixels() {
        // 1 pixel in 200 (0.5 %) in the window with ×4, the rest bright with ×2: mean of all ratios.
        let inWindow = [SIMD4<Float>(0.045, 0.045, 0.045, 1)]
        let outside = [SIMD4<Float>](repeating: SIMD4(2, 2, 2, 1), count: 199)
        let anchor = ExposureAnchor.stops(
            linear: inWindow + outside, profile: Self.scaled(inWindow, by: 4) + Self.scaled(outside, by: 2))
        let expected = (2.0 + 199 * 1) / 200
        #expect(abs(anchor - expected) < Self.arithmeticTolerance, "anchor \(anchor), expected \(expected)")
    }

    @Test func unusablePixelsGiveZero() {
        let black = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: 16)
        #expect(ExposureAnchor.stops(linear: black, profile: black) == 0)
        #expect(ExposureAnchor.stops(linear: [], profile: []) == 0)
        #expect(ExposureAnchor.stops(linear: Self.linear, profile: Array(Self.linear.dropLast())) == 0, "sizes differ")
    }

    @Test func nonFinitePixelsAreSkipped() {
        let nan = [SIMD4<Float>](repeating: SIMD4(.nan, 0.2, 0.2, 1), count: 4)
        let anchor = ExposureAnchor.stops(linear: Self.linear + nan, profile: Self.scaled(Self.linear, by: 4) + nan)
        #expect(abs(anchor - 2) < Self.arithmeticTolerance, "anchor \(anchor)")
    }

    @Test(arguments: [(Float(256), 5.0), (Float(1.0 / 16), -2.0)])
    func anchorIsClamped(gain: Float, expected: Double) {
        #expect(ExposureAnchor.stops(linear: Self.linear, profile: Self.scaled(Self.linear, by: gain)) == expected)
    }
}
