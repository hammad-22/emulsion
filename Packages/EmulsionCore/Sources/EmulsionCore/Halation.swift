import Foundation
import simd

/// Halation: light that crosses the emulsion, reflects at the back of the base and re-exposes the
/// emulsion from behind (`docs/FILM-THEORY.md` §6.1). Linear in exposure: no threshold, no limiter.
/// The kernels `halationSource` and `halationAdd` mirror this; names match.
enum Halation {
    /// The spread of the returned light: a unit-volume sum of 2D Gaussians, sigmas in base
    /// thicknesses. The 3-Gaussian fit (one negative weight) of the derived single-bounce profile,
    /// max |Δ encircled energy| 0.0615 (`Tools/halation-kernel`, `recommended`).
    static let weights = SIMD3<Double>(-0.99816922, 1.7270851, 0.27108408)
    static let sigmasInBaseThicknesses = SIMD3<Double>(1.3078016, 1.7310926, 6.10456)

    /// Kernel value h·t² at `radius` base thicknesses (per unit returned light).
    static func profile(radiusInBaseThicknesses radius: Double) -> Double {
        let variance = sigmasInBaseThicknesses * sigmasInBaseThicknesses
        let gaussians = (0..<3).map { exp(-radius * radius / (2 * variance[$0])) / (2 * .pi * variance[$0]) }
        return simd_dot(weights, SIMD3(gaussians))
    }

    /// Share of the returned light that lands within `radius` base thicknesses.
    static func encircledEnergy(radiusInBaseThicknesses radius: Double) -> Double {
        let variance = sigmasInBaseThicknesses * sigmasInBaseThicknesses
        return simd_dot(weights, SIMD3((0..<3).map { 1 - exp(-radius * radius / (2 * variance[$0])) }))
    }

    /// Image pixels per base thickness: the image's long edge spans the assumed frame width.
    static func pixelsPerBaseThickness(longEdge: Double) -> Double {
        FilmLook.baseThicknessMicrometres / (FilmLook.frameWidthMillimetres * 1000) * longEdge
    }

    /// k per layer (red, green, blue): returned light per unit of the exposing light. The amount
    /// (0…1) reads as the share of the exposing light that scatters into the base (a modelling
    /// assumption). Blue is 0: the yellow filter layer stops blue light above the green and red layers.
    static func layerReturn(amount: Double, backing: AntihalationBacking) -> SIMD3<Double> {
        let red = amount * FilmLook.halationReturnFraction * backing.returnFraction
        return SIMD3(red, red * FilmLook.halationGreenShare, 0)
    }

    /// Layer exposure with its halation: E′ = (E + k·glow) / (1 + k). Film speed is defined on
    /// uniform patches, which already include their own halation, so a uniform field is unchanged.
    static func exposureWithHalation(_ exposure: SIMD3<Double>, glow: SIMD3<Double>, layerReturn k: SIMD3<Double>) -> SIMD3<Double> {
        (exposure + k * glow) / (1 + k)
    }
}
