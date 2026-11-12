import CoreImage
import simd

extension FilmModel {
    /// Kernel arguments for `filmSystem`, with user printer lights (log10), exposure (stops) and
    /// saturation folded in (the ABI is documented above `filmRender` in Emulsion.ci.metal). The
    /// film kernels take the scene, glow and noise samplers before these and, after them,
    /// `relativeArguments` (`filmSystemRelative` only), `Halation.kernelArguments` and
    /// `Grain.kernelArguments`.
    func kernelArguments(lights: SIMD3<Double> = .zero, exposure: Double = 0, saturation: Double = 1) -> [CIVector] {
        let total = printerLights + lights
        return CIVector.rows(of: sensitivity) + [
            CIVector(negativeGamma, w: negativeRange),
            CIVector(negativeOffset, w: exposure),
            CIVector(printGamma, w: printRange),
            CIVector(x: printDmin, y: printShape, z: saturation, w: highlightChromaRetention),
            CIVector(total, w: 0),
        ] + CIVector.rows(of: printDyes)
    }

    /// Kernel arguments for `displayToScene`: the zero-edit film, the soft ends and the rows of
    /// the inverse layer sensitivity.
    func displayToSceneArguments() -> [CIVector] {
        kernelArguments() + [softEnds.vector] + CIVector.rows(of: sensitivity.inverse)
    }

    /// The arguments `filmSystemRelative` takes after `kernelArguments`: the soft ends and the
    /// calibrated printer lights the zero-edit print is made with.
    var relativeArguments: [CIVector] { [softEnds.vector, CIVector(printerLights, w: 0)] }
}

extension FilmModel.SoftEnds {
    /// (kneeHigh, a, kneeLow, b), the kernels' `ends`.
    var vector: CIVector { CIVector(x: kneeHigh, y: a, z: kneeLow, w: b) }
}
