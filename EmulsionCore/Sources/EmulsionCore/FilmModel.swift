import Foundation
import simd

/// Emulsion's look as a photochemical system rather than a curve or LUT:
///
///   scene light ─▶ negative layers (sensitivity crosstalk) ─▶ H&D curves → dye density
///               ─▶ print exposure through the negative (printer lights)
///               ─▶ print H&D curves → print dye density (unwanted absorptions)
///               ─▶ viewing: light = 10^−(density − paper white)
///
/// All math is in linear Display P3 scene light and log10 exposure / optical density. The
/// Metal kernel `filmSystem` implements the same equations; this Swift mirror is used to
/// calibrate the printer lights and to verify the kernel numerically.
public struct FilmModel: Sendable, Equatable {
    /// Layer spectral overlap as a fixed 3×3 mix. Rows sum to 1, so neutral exposure stays
    /// neutral before the curves. The small negative terms reduce crosstalk to keep colors clean;
    /// this is a fitted basis change, not a model of density-dependent interimage (DIR) effects.
    /// Strongly saturated light can drive a layer's exposure negative, which is clamped.
    public var sensitivity = simd_double3x3(rows: [
        SIMD3(1.07, -0.05, -0.02),
        SIMD3(-0.04, 1.08, -0.04),
        SIMD3(-0.01, -0.07, 1.08),
    ])

    /// Negative characteristic curves (per layer R, G, B): density = dmin + range·logistic.
    /// `negativeGamma` is the slope at the curve center (+0.45 log10 above mid-gray), about 0.6,
    /// typical of camera negative; very wide latitude.
    public var negativeGamma = SIMD3<Double>(0.60, 0.62, 0.65)
    public var negativeRange = 3.0
    public var negativeOffset = SIMD3<Double>(0.45, 0.45, 0.45)  // log10 exposure of the curve center vs mid-gray

    /// Print stock: high contrast, deep blacks, paper white at dmin.
    public var printGamma = SIMD3<Double>(2.20, 2.15, 2.05)
    public var printDmin = 0.06
    public var printRange = 3.3
    /// Richards shape of the print curve (1 = symmetric logistic). Below 1 the highlight toe
    /// is shorter and sharper: whites arrive cleanly and bright colors keep their chroma
    /// longer instead of being squeezed together over many stops.
    public var printShape = 0.5
    /// Unwanted absorptions of the print dyes (density cross-contamination), rows sum to 1.
    public var printDyes = simd_double3x3(rows: [
        SIMD3(0.94, 0.05, 0.01),
        SIMD3(0.04, 0.90, 0.06),
        SIMD3(0.01, 0.07, 0.92),
    ])

    /// Highlight chroma retention (the one non-physical step). Per-layer shoulders flatten
    /// bright saturated light (neon, stage lights) far faster than its brightness warrants;
    /// above +1.5 stops on the brightest channel the result blends toward a ratio-preserving
    /// rendering through the same neutral response. Below +1.5 stops the result is unchanged.
    /// Artistic, not physical: bright neutrals lose part of their printer-light timing, and very
    /// bright saturated colors keep a tint instead of reaching white (HAM-99).
    public var highlightChromaRetention = 0.6

    /// Scene mid-gray (18%) is timed to this display-linear value on every channel.
    public var middleGrayOut = 0.17

    /// Printer lights (log10 print exposure per channel) solved for a neutral mid-gray.
    public private(set) var printerLights = SIMD3<Double>(repeating: 0)

    public init() { calibrate() }

    // MARK: Equations

    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// log10 scene exposure (per layer, relative to mid-gray) → negative density.
    public func negativeDensity(_ logE: SIMD3<Double>) -> SIMD3<Double> {
        let k = 4 * negativeGamma / negativeRange
        return SIMD3((0..<3).map { negativeRange * Self.logistic(k[$0] * (logE[$0] - negativeOffset[$0])) })
    }

    /// log10 print exposure → print density (before dye cross-absorption).
    public func printDensity(_ logP: SIMD3<Double>) -> SIMD3<Double> {
        let k = 4 * printGamma / printRange
        return SIMD3((0..<3).map { printDmin + printRange * pow(Self.logistic(k[$0] * logP[$0]), 1 / printShape) })
    }

    /// Scene-linear Display P3 → display-linear Display P3 (before gamut mapping).
    /// `lights` adds user printer lights (log10) to the calibrated ones.
    public func render(_ scene: SIMD3<Double>, lights: SIMD3<Double> = .zero, saturation: Double = 1) -> SIMD3<Double> {
        let y = dot(scene, SIMD3(0.2289746, 0.6917385, 0.0792869))
        let s = SIMD3(repeating: y) + (scene - SIMD3(repeating: y)) * saturation
        let perLayer = system(s, lights: lights)
        let m = max(s.max(), 1e-7)
        let w = highlightChromaRetention * Self.smoothstep(1.5, 4.0, log2(m / 0.18))
        guard w > 0 else { return perLayer }
        let ratioPreserving = s * (system(SIMD3(repeating: m), lights: lights).y / m)
        return perLayer + (ratioPreserving - perLayer) * w
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// The photochemical chain itself.
    func system(_ s: SIMD3<Double>, lights: SIMD3<Double>) -> SIMD3<Double> {
        let exposure = simd_max(sensitivity * s, SIMD3(repeating: 1e-7))
        let logE = SIMD3((0..<3).map { log10(exposure[$0] / 0.18) })
        let dNeg = negativeDensity(logE)
        // More negative density → less light reaches the print.
        let logP = printerLights + lights - dNeg
        let dPrint = printDyes * printDensity(logP)
        let paper = printDyes * SIMD3(repeating: printDmin)
        return SIMD3((0..<3).map { pow(10, -(dPrint[$0] - paper[$0])) })
    }

    /// Time the print: solve printer lights so 18% gray prints neutral at `middleGrayOut`.
    /// Dye cross-absorption couples channels, so iterate the per-channel solves.
    mutating func calibrate() {
        printerLights = .zero
        for _ in 0..<8 {
            for c in 0..<3 {
                var lo = -4.0
                var hi = 4.0
                for _ in 0..<60 {
                    let mid = (lo + hi) / 2
                    var trial = printerLights
                    trial[c] = mid
                    var model = self
                    model.printerLights = trial
                    // More print exposure → denser print → darker.
                    if model.render(SIMD3(repeating: 0.18))[c] > middleGrayOut { lo = mid } else { hi = mid }
                }
                printerLights[c] = (lo + hi) / 2
            }
        }
    }
}
