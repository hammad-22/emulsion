import CoreImage
import simd

extension FilmModel {
    /// Kernel arguments for `filmSystem` / `displayToScene`, with user printer lights
    /// (log10), exposure (stops) and saturation folded in.
    func kernelArguments(lights: SIMD3<Double> = .zero, exposure: Double = 0, saturation: Double = 1) -> [CIVector] {
        let total = printerLights + lights
        return CIVector.rows(of: sensitivity) + [
            CIVector(x: negativeGamma.x, y: negativeGamma.y, z: negativeGamma.z, w: negativeRange),
            CIVector(x: negativeOffset.x, y: negativeOffset.y, z: negativeOffset.z, w: exposure),
            CIVector(x: printGamma.x, y: printGamma.y, z: printGamma.z, w: printRange),
            CIVector(x: printDmin, y: printShape, z: saturation, w: highlightChromaRetention),
            CIVector(x: total.x, y: total.y, z: total.z, w: 0),
        ] + CIVector.rows(of: printDyes)
    }
}
