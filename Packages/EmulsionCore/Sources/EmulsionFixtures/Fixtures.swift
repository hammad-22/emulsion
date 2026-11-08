import CoreGraphics
import CoreImage
import Foundation
import simd

/// Reproducible synthetic images and perceptual measurements for Emulsion's tests.
/// Nothing here reads a photo library.
public enum Fixtures {
    public static let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    /// Float RGBA image in an encoded color space, bottom row first (Core Image convention).
    /// A nil `space` keeps raw code values (no color matching), as for camera log input.
    public static func image(
        width: Int, height: Int, space: CGColorSpace?,
        _ color: (Int, Int) -> SIMD3<Float>
    ) -> CIImage {
        var values = [SIMD4<Float>](repeating: .zero, count: width * height)
        // CIImage bitmap rows are top-down; generate so that y=0 is the bottom row.
        for row in 0..<height {
            for x in 0..<width {
                let c = color(x, height - 1 - row)
                values[row * width + x] = SIMD4(c, 1)
            }
        }
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(
            bitmapData: data, bytesPerRow: width * 16,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
    }

    public static func row(_ colors: [SIMD3<Float>], space: CGColorSpace?) -> CIImage {
        image(width: colors.count, height: 1, space: space) { x, _ in colors[x] }
    }

    // MARK: Fixtures

    /// sRGB / Display P3 transfer function (linear → encoded).
    public static func encode(_ x: Float) -> Float { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }

    public static func grayRamp(steps: Int = 256) -> [SIMD3<Float>] {
        (0..<steps).map {
            let v = Float($0) / Float(steps - 1)
            return SIMD3(v, v, v)
        }
    }

    // MARK: Measurement

    /// OKLab of an image, via linear sRGB, bottom row first.
    public static func oklab(_ image: CIImage) -> [SIMD3<Double>] {
        floats(image, space: linearSRGB).map(toOKLab)
    }

    /// Linear sRGB (extended) values, bottom row first.
    public static func linear(_ image: CIImage) -> [SIMD3<Double>] {
        floats(image, space: linearSRGB)
    }
    /// Encoded values in `space` before any 8-bit quantization.
    public static func encodedFloats(_ image: CIImage, space: CGColorSpace) -> [SIMD3<Double>] {
        floats(image, space: space)
    }
    private static let readbackContext = CIContext(options: [
        .workingColorSpace: linearSRGB, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false,
    ])

    static func floats(_ image: CIImage, space: CGColorSpace) -> [SIMD3<Double>] {
        let w = Int(image.extent.width)
        let h = Int(image.extent.height)
        var f = [Float](repeating: 0, count: w * h * 4)
        readbackContext.render(image, toBitmap: &f, rowBytes: w * 16, bounds: image.extent, format: .RGBAf, colorSpace: space)
        var out = [SIMD3<Double>](repeating: .zero, count: w * h)
        for row in 0..<h {
            for x in 0..<w {
                let i = (row * w + x) * 4
                out[(h - 1 - row) * w + x] = SIMD3(Double(f[i]), Double(f[i + 1]), Double(f[i + 2]))
            }
        }
        return out
    }
    public static func toOKLab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let l = 0.4122214708 * rgb.x + 0.5363325363 * rgb.y + 0.0514459929 * rgb.z
        let m = 0.2119034982 * rgb.x + 0.6806995451 * rgb.y + 0.1073969566 * rgb.z
        let s = 0.0883024619 * rgb.x + 0.2817188376 * rgb.y + 0.6299787005 * rgb.z
        let c = { (v: Double) in v < 0 ? -pow(-v, 1.0 / 3) : pow(v, 1.0 / 3) }
        let (l_, m_, s_) = (c(l), c(m), c(s))
        return SIMD3(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    /// Euclidean OKLab difference ×100 (≈ "just noticeable" near 1–2).
    public static func deltaE(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return 100 * (d * d).sum().squareRoot()
    }
    public static func hue(_ lab: SIMD3<Double>) -> Double { atan2(lab.z, lab.y) * 180 / .pi }
    public static func chroma(_ lab: SIMD3<Double>) -> Double { hypot(lab.y, lab.z) }
    public static func hueDifference(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        abs((hue(a) - hue(b) + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

}

// MARK: Scene-light fixtures (linear sRGB working values; 0.18 is mid-gray)

public enum SceneFixtures {
    public static let linear = Fixtures.linearSRGB
    public static let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!

    /// Neutral exposure wedge from −8 to +6 stops around mid-gray.
    public static func wedge(steps: Int = 141) -> (image: CIImage, stops: [Double]) {
        let stops = (0..<steps).map { -8 + 14 * Double($0) / Double(steps - 1) }
        let image = Fixtures.image(width: steps, height: 1, space: linear) { x, _ in
            SIMD3(repeating: Float(0.18 * pow(2, stops[x])))
        }
        return (image, stops)
    }
    /// Flat scene patch of one value, any size (grain statistics, preview/export).
    public static func flat(_ value: Float, width: Int = 256, height: Int = 256) -> CIImage {
        Fixtures.image(width: width, height: height, space: linear) { _, _ in SIMD3(repeating: value) }
    }
    /// A small, very bright source on a dark scene (halation).
    public static func highlightPoint(size: Int = 400, radius: Float = 6, level: Float = 40) -> CIImage {
        Fixtures.image(width: size, height: size, space: linear) { x, y in
            hypot(Float(x - size / 2), Float(y - size / 2)) < radius * Float(size) / 400 ? SIMD3(repeating: level) : SIMD3(repeating: 0.02)
        }
    }
    /// Colored scene patches (linear Display P3 → working space), incl. saturated neon.
    public static let patchesP3: [SIMD3<Float>] = [
        [0.40, 0.20, 0.13], [0.12, 0.20, 0.45], [0.10, 0.25, 0.06],
        [0.55, 0.04, 0.03], [0.02, 0.35, 0.60], [0.60, 0.05, 0.50], [0.18, 0.18, 0.18],
    ]
    public static func patches(cell: Int = 64) -> CIImage {
        Fixtures.image(width: cell * patchesP3.count, height: cell, space: linearP3) {
            x, _ in
            patchesP3[x / cell]
        }
    }
}
