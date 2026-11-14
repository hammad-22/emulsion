import CoreImage
import simd

extension FilmModel {
    /// Kernel arguments for `filmSystem`, with user printer lights (log10), exposure (stops) and
    /// saturation folded in (the ABI is documented above `filmRender` in Emulsion.ci.metal). Gamma
    /// and the widths are folded into the printing-density rows and the widths passed as
    /// reciprocals, so the kernel computes printingDensity · negativeDyeAmount without dividing.
    func kernelArguments(lights: SIMD3<Double> = .zero, exposure: Double = 0, saturation: Double = 1) -> [CIVector] {
        let total = printerLights + lights
        let toeRows = printingDensity * simd_double3x3(diagonal: negativeGamma * negativeToeWidth)
        let shoulderRows = printingDensity * simd_double3x3(diagonal: negativeGamma * negativeShoulderWidth)
        let toeRate = 1 / negativeToeWidth
        let shoulderRate = 1 / negativeShoulderWidth
        return CIVector.rows(of: sensitivity) + [
            CIVector(x: negativeToeExposure.x, y: negativeToeExposure.y, z: negativeToeExposure.z, w: exposure),
            CIVector(x: toeRate.x, y: toeRate.y, z: toeRate.z, w: 0),
            CIVector(x: negativeShoulderExposure.x, y: negativeShoulderExposure.y, z: negativeShoulderExposure.z, w: 0),
            CIVector(x: shoulderRate.x, y: shoulderRate.y, z: shoulderRate.z, w: 0),
        ] + CIVector.rows(of: toeRows) + CIVector.rows(of: shoulderRows) + [
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
