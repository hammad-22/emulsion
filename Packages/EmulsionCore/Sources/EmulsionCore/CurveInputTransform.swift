import CoreImage
import simd

/// Samples → formula input as three affine rows per clip (docs/CONSTANTS.md, "CurveInputTransform").
struct CurveInputTransform {
    let linear: simd_double3x3
    let offset: SIMD3<Double>

    init(rgbIn range: SignalRange, sampleUnitsPerCode k: Double, for space: InputColorSpace) {
        let toSignal = simd_double3x3(diagonal: SIMD3(repeating: 1 / (range.lumaSpan * k)))
        self.init(toSignal: toSignal, signalOffset: SIMD3(repeating: -range.lumaBlack / range.lumaSpan), for: space)
    }

    init(ycbcrIn signal: VideoSignal, sampleUnitsPerCode k: Double, for space: InputColorSpace) {
        let r = signal.range
        let scale = simd_double3x3(diagonal: SIMD3(r.lumaSpan * k, r.chromaSpan * k, r.chromaSpan * k)).inverse
        let center = SIMD3(-r.lumaBlack / r.lumaSpan, -SignalRange.chromaCenter / r.chromaSpan, -SignalRange.chromaCenter / r.chromaSpan)
        self.init(toSignal: signal.matrix.toRGB * scale, signalOffset: signal.matrix.toRGB * center, for: space)
    }

    private init(toSignal: simd_double3x3, signalOffset: SIMD3<Double>, for space: InputColorSpace) {
        let (scale, curveOffset) = space.curveInputFromSignal
        linear = toSignal * scale
        offset = signalOffset * scale + curveOffset
    }

    func apply(_ samples: SIMD3<Double>) -> SIMD3<Double> { linear * samples + offset }

    /// The kernel's `r0`, `r1`, `r2` rows.
    var rows: [CIVector] {
        (0..<3).map { CIVector(x: linear[0][$0], y: linear[1][$0], z: linear[2][$0], w: offset[$0]) }
    }
}
