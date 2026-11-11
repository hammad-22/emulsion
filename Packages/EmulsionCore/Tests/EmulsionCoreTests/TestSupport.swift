import CoreImage
import EmulsionFixtures
import ImageIO
import XCTest
import simd

@testable import EmulsionCore

/// Shared renderer and measurement helpers for the engine tests.
class EmulsionTestCase: XCTestCase {
    static let sharedRenderer = try! Renderer()
    var renderer: Renderer { Self.sharedRenderer }
    let p3 = Renderer.outputSpace

    func render(_ scene: CIImage, _ a: Adjustments = .neutral) throws -> CIImage {
        try renderer.render(Negative(image: scene, contract: .sceneReferred), a)
    }
    /// Encoded Display P3 values ×255, before 8-bit rounding.
    func codes(_ image: CIImage) -> [SIMD3<Double>] { Self.codes(image) }
    static func codes(_ image: CIImage) -> [SIMD3<Double>] {
        Fixtures.encodedFloats(image, space: Renderer.outputSpace).map { $0 * 255 }
    }
    /// Display P3 luminance weights.
    func luma(_ c: SIMD3<Double>) -> Double { 0.2290 * c.x + 0.6917 * c.y + 0.0793 * c.z }
    func sd(_ v: [Double]) -> Double {
        let m = v.reduce(0, +) / Double(v.count)
        return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
    }
    /// Index of pixel (x, y) in a fixture's bottom-row-first pixel array.
    func pixel(x: Int, y: Int, width: Int) -> Int { Self.pixel(x: x, y: y, width: width) }
    static func pixel(x: Int, y: Int, width: Int) -> Int { y * width + x }
    /// Linear Display P3 → OKLab.
    func p3ToLab(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let m = simd_double3x3(rows: [
            SIMD3(1.2249401763, -0.2249401763, 0), SIMD3(-0.0420569547, 1.0420569547, 0),
            SIMD3(-0.0196375546, -0.0786360456, 1.0982736001),
        ])
        return Fixtures.toOKLab(m * p)
    }
}
