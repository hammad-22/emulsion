import CoreImage
import Foundation
import simd

/// Grain (MOV-30, `docs/FILM-THEORY.md` §6.2): a random fluctuation of the negative's dye density,
/// per layer, printed through the film. Each layer's density gets σ·n, with n white unit-variance
/// noise per pixel (kernel `grainNoise`) and σ the datasheet's granularity at that layer's exposure,
/// scaled from the datasheet's aperture to the pixel by Selwyn's law. The print's own granularity
/// is not modelled. The kernels `filmSystem` and `filmSystemRelative` mirror this; names match.
enum Grain {
    /// Table knots: a layer's log10 exposure relative to mid-gray (18% gray at camera stop 0; one
    /// stop is log10 2). The engine's density frame is generic (G-1), so σ is indexed by exposure.
    static let logExposureKnots = [-2.4, -2.01, -1.7, -1.27, -0.15, 0.38, 0.91, 2.4]
    /// Diffuse rms granularity σ_D at the datasheet's 48 µm aperture, at each knot. Source: Kodak
    /// H-1-5207 (rev. 3-26) granularity chart, digitized and read by density (chart x = 2.557 +
    /// 0.86·log exposure) in `Tools/grain-reference/granularity` (`engine_table`, minimax values;
    /// piecewise-linear error ≤ 5.2% against the trace). Held at the end values outside the knots.
    static let sigmaD48Red = [0.00531, 0.0051, 0.00689, 0.01035, 0.00609, 0.00585, 0.00528, 0.00448]
    static let sigmaD48Green = [0.00565, 0.00516, 0.00732, 0.01063, 0.00622, 0.00612, 0.00703, 0.00535]
    static let sigmaD48Blue = [0.01169, 0.012, 0.01617, 0.01612, 0.01185, 0.0142, 0.01261, 0.0084]
    /// The datasheet's microdensitometer aperture: "a 48-micrometre aperture" (circular).
    static let datasheetApertureDiameterMicrometres = 48.0
    /// Clump σ per unit of size, film µm: s² pixels of correlation area at 48 MP, as look-reviewed (artistic).
    static let clumpSigmaMicrometresPerSize = FilmLook.micrometresPerPixel(longEdge: 8064) / (4 * Double.pi).squareRoot()
    /// Below this clump σ (pixels) a neighbour's tap weight is under exp(−8), so the blur is skipped.
    static let minimumClumpSigmaPixels = 0.25

    /// σ_D at 48 µm per layer (red, green, blue) for each layer's log10 exposure: the kernel's
    /// `densitySigma` before the per-pixel scale, a sum over the seven segments.
    static func sigmaD48(logExposure: SIMD3<Double>) -> SIMD3<Double> {
        let rows = knotValues
        var sigma = rows[0]
        for i in 0..<(logExposureKnots.count - 1) {
            let t = (logExposure - logExposureKnots[i]) / (logExposureKnots[i + 1] - logExposureKnots[i])
            sigma += (rows[i + 1] - rows[i]) * simd_clamp(t, .zero, .one)
        }
        return sigma
    }

    /// σ(pixel) / σ(48 µm) by Selwyn's law, σ√area constant: √(π·24²) / p for a square pixel of side
    /// p µm. An approximation that assumes the aperture is much larger than the grain; for 0.5 µm
    /// grains the Boolean-model reference finds it within 4.1% for p ≥ 6.2 µm and 7–10% high at 3.1 µm.
    static func selwynScale(pixelPitchMicrometres p: Double) -> Double {
        (Double.pi).squareRoot() * datasheetApertureDiameterMicrometres / 2 / p
    }

    /// Density standard deviation per pixel and layer before the clump blur (kernel `densitySigma`).
    /// `amount` 1 is the datasheet's granularity on the assumed frame; `size` s scales it as a frame
    /// s times narrower would (Selwyn), so the clump blur, which keeps low-frequency power, gives
    /// that frame's granularity at any aperture wider than a clump. See docs/FILM-THEORY.md §6.2.
    static func densitySigma(logExposure: SIMD3<Double>, amount: Double, size: Double, longEdge: Double) -> SIMD3<Double> {
        sigmaD48(logExposure: logExposure) * scale(amount: amount, size: size, longEdge: longEdge)
    }

    /// Density added to the negative layers for `noise` (kernel `grainDensity`).
    static func density(
        logExposure: SIMD3<Double>, noise: SIMD3<Double>, amount: Double, size: Double, color: Double, longEdge: Double
    ) -> SIMD3<Double> {
        FilmModel.saturated(densitySigma(logExposure: logExposure, amount: amount, size: size, longEdge: longEdge) * noise, color)
    }

    /// The clump blur's σ in pixels for `size` on an image with this long edge.
    static func clumpSigmaPixels(size: Double, longEdge: Double) -> Double {
        size * clumpSigmaMicrometresPerSize / FilmLook.micrometresPerPixel(longEdge: longEdge)
    }

    /// The kernels' g0…g7, (σ red, σ green, σ blue, knot) per knot with σ per pixel, then grainColor.
    static func kernelArguments(amount: Double, size: Double, color: Double, longEdge: Double) -> [Any] {
        let s = scale(amount: amount, size: size, longEdge: longEdge)
        let knots = zip(knotValues, logExposureKnots).map { sigma, knot in CIVector(sigma * s, w: knot) }
        return knots + [color]
    }

    private static func scale(amount: Double, size: Double, longEdge: Double) -> Double {
        amount * size * selwynScale(pixelPitchMicrometres: FilmLook.micrometresPerPixel(longEdge: longEdge))
    }

    private static let knotValues = (0..<logExposureKnots.count).map { SIMD3(sigmaD48Red[$0], sigmaD48Green[$0], sigmaD48Blue[$0]) }
}

extension Kernels {
    /// Grain noise over `extent`: rgb = independent zero-mean, unit-variance values per pixel and
    /// layer, white, deterministic for `seed` (kernel `grainNoise`).
    func grainNoise(_ extent: CGRect, seed: Double) throws -> CIImage {
        try run(grainNoise, extent, [seed])
    }

    /// `grainNoise` blurred into clumps for grain `size` (`Grain.clumpSigmaPixels`), sized to the extent's long edge.
    func grainNoise(_ extent: CGRect, seed: Double, size: Double) throws -> CIImage {
        let sigma = Grain.clumpSigmaPixels(size: size, longEdge: max(extent.width, extent.height))
        guard sigma >= Grain.minimumClumpSigmaPixels else { return try grainNoise(extent, seed: seed) }
        let margin = (4 * sigma).rounded(.up)
        return try gaussianBlur(grainNoise(extent.insetBy(dx: -margin, dy: -margin), seed: seed), sigma: sigma).cropped(to: extent)
    }
}
