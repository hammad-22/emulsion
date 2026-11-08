import CoreImage
import simd

extension CIVector {
    /// One matrix row as a kernel argument (`w` unused).
    convenience init(row r: Int, of m: simd_double3x3) {
        self.init(x: m[0][r], y: m[1][r], z: m[2][r], w: 0)
    }

    static func rows(of m: simd_double3x3) -> [CIVector] { (0..<3).map { CIVector(row: $0, of: m) } }
}

extension CIImage {
    func lanczosScaled(by scale: CGFloat) -> CIImage {
        applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
}
