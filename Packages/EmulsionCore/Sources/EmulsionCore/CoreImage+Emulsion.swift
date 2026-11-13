import CoreImage
import simd

extension simd_double3x3 {
    /// The three rows, as `simd_double3x3(rows:)` takes them (simd stores columns).
    var rows: [SIMD3<Double>] { (0..<3).map { r in SIMD3(self[0][r], self[1][r], self[2][r]) } }
}

extension CIVector {
    /// The matrix rows as kernel arguments (`w` unused).
    static func rows(of m: simd_double3x3) -> [CIVector] { m.rows.map { CIVector(x: $0.x, y: $0.y, z: $0.z, w: 0) } }
}

extension CIImage {
    func lanczosScaled(by scale: CGFloat) -> CIImage {
        applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
}
