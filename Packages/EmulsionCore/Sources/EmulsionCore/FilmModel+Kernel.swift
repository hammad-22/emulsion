import CoreImage
import simd

extension FilmModel {
    /// Kernel arguments for `filmSystem`, with user printer lights (log10), exposure (stops) and
    /// saturation folded in (the ABI is documented above `filmRender` in Emulsion.ci.metal). The
    /// film kernels take the grain noise sampler before these and `Grain.kernelArguments` after them.
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

    /// Kernel arguments for `displayToScene`: the zero-edit film, the soft ends and the rows of
    /// the inverse layer sensitivity.
    func displayToSceneArguments() -> [CIVector] {
        kernelArguments() + [softEnds.vector] + CIVector.rows(of: sensitivity.inverse)
    }

    /// Kernel arguments for `filmSystemRelative`: as `kernelArguments`, plus the soft ends and the
    /// calibrated printer lights the zero-edit print is made with.
    func relativeKernelArguments(lights: SIMD3<Double>, exposure: Double, saturation: Double) -> [CIVector] {
        kernelArguments(lights: lights, exposure: exposure, saturation: saturation) + [
            softEnds.vector, CIVector(x: printerLights.x, y: printerLights.y, z: printerLights.z, w: 0),
        ]
    }
}

extension FilmModel.SoftEnds {
    /// (kneeHigh, a, kneeLow, b), the kernels' `ends`.
    var vector: CIVector { CIVector(x: kneeHigh, y: a, z: kneeLow, w: b) }
}
