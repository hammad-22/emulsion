import CoreGraphics
import CoreImage
import Foundation
import simd

/// Display-referred fixtures: finished pictures encoded in Display P3, as a JPEG or HEIC decodes.
public enum DisplayFixtures {
    public static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// P3-encoded patches: primaries, secondaries, saturated sky and coral, skin, and
    /// mid-saturation versions.
    public static let patches: [(name: String, code: SIMD3<Float>)] = [
        ("red", [1, 0, 0]), ("green", [0, 1, 0]), ("blue", [0, 0, 1]),
        ("cyan", [0, 1, 1]), ("magenta", [1, 0, 1]), ("yellow", [1, 1, 0]),
        ("azure", [0, 0.6, 1]), ("coral", [0.9, 0.3, 0.2]), ("sky", [0.2, 0.5, 1]), ("skin", [0.86, 0.64, 0.52]),
        ("red 50%", [0.75, 0.25, 0.25]), ("green 50%", [0.3, 0.7, 0.3]), ("blue 50%", [0.3, 0.35, 0.75]),
        ("yellow 50%", [0.7, 0.65, 0.3]), ("magenta 50%", [0.65, 0.35, 0.65]), ("cyan 50%", [0.3, 0.65, 0.7]),
    ]

    /// Layout of `proofChart`, bottom row first: a 256-step gray ramp (one code per column), a
    /// near-white sky gradient rising to code 255, then two rows of patches.
    public static let chartWidth = 256
    public static let band = 16
    public static let patchCell = 32
    public static let patchesPerRow = 8
    public static let grayRow = band / 2
    public static let skyRow = band + band / 2

    /// The sky gradient's P3 code at column `x` (blue-ish, reaching white at the right edge).
    public static func sky(_ x: Int) -> SIMD3<Float> {
        let t = Float(x) / Float(chartWidth - 1)
        return SIMD3(0.55, 0.72, 0.9) + SIMD3(0.45, 0.28, 0.1) * t
    }

    /// Center of patch `i` in chart pixels.
    public static func patchCenter(_ i: Int) -> (x: Int, y: Int) {
        (i % patchesPerRow * patchCell + patchCell / 2, 2 * band + i / patchesPerRow * patchCell + patchCell / 2)
    }

    public static func proofChart() -> CIImage {
        let rows = (patches.count + patchesPerRow - 1) / patchesPerRow
        return Fixtures.image(width: chartWidth, height: 2 * band + rows * patchCell, space: displayP3) { x, y in
            if y < band { return SIMD3(repeating: Float(x) / 255) }
            if y < 2 * band { return sky(x) }
            let i = (y - 2 * band) / patchCell * patchesPerRow + x / patchCell
            return i < patches.count ? patches[i].code : SIMD3(repeating: 0.5)
        }
    }
}
