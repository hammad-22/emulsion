import CoreImage
import simd

extension FilmModel {
    /// Kernel arguments for `filmSystem` / `displayToScene`, with user printer lights
    /// (log10), exposure (stops) and saturation folded in.
    func kernelArguments(lights: SIMD3<Double> = .zero, exposure: Double = 0, saturation: Double = 1) -> [CIVector] {
        let total = printerLights + lights
        return [
            CIVector(row: 0, of: sensitivity), CIVector(row: 1, of: sensitivity), CIVector(row: 2, of: sensitivity),
            CIVector(x: negativeGamma.x, y: negativeGamma.y, z: negativeGamma.z, w: negativeRange),
            CIVector(x: negativeOffset.x, y: negativeOffset.y, z: negativeOffset.z, w: exposure),
            CIVector(x: printGamma.x, y: printGamma.y, z: printGamma.z, w: printRange),
            CIVector(x: printDmin, y: printShape, z: saturation, w: highlightChromaRetention),
            CIVector(x: total.x, y: total.y, z: total.z, w: 0),
            CIVector(row: 0, of: printDyes), CIVector(row: 1, of: printDyes), CIVector(row: 2, of: printDyes),
        ]
    }
}

extension CIVector {
    /// One matrix row as a kernel argument (`w` unused).
    convenience init(row r: Int, of m: simd_double3x3) {
        self.init(x: m[0][r], y: m[1][r], z: m[2][r], w: 0)
    }
}
