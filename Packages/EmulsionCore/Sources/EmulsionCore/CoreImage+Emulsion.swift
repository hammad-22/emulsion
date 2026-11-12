import CoreImage
import simd

extension simd_double3x3 {
    /// The three rows, as `simd_double3x3(rows:)` takes them (simd stores columns).
    var rows: [SIMD3<Double>] { (0..<3).map { r in SIMD3(self[0][r], self[1][r], self[2][r]) } }
}

extension CIVector {
    /// The matrix rows as kernel arguments (`w` unused).
    static func rows(of m: simd_double3x3) -> [CIVector] { m.rows.map { CIVector(x: $0.x, y: $0.y, z: $0.z, w: 0) } }

    convenience init(_ v: SIMD3<Double>, w: Double) { self.init(x: v.x, y: v.y, z: v.z, w: w) }
}

extension CIImage {
    /// Each 2×2 block averaged into one pixel (bilinear sampling at the blocks' corners), as its own
    /// intermediate: Core Image would otherwise fold successive halvings into one sparse sample and
    /// drop small highlights.
    func halved() -> CIImage {
        transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)).insertingIntermediate(cache: false)
    }

    func lanczosScaled(by scale: CGFloat) -> CIImage {
        applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
}
