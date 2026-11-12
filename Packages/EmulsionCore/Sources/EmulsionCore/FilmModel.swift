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
    public let sensitivity: simd_double3x3

    /// Negative characteristic curves (per layer R, G, B): density = range·logistic.
    /// `negativeGamma` is the slope (density per log10 exposure) at the curve center,
    /// `negativeOffset` log10 exposure above mid-gray.
    public let negativeGamma: SIMD3<Double>
    public let negativeRange: Double
    public let negativeOffset: SIMD3<Double>

    /// Print stock: high contrast, deep blacks, paper white at dmin.
    public let printGamma: SIMD3<Double>
    /// Paper-white density. Cancels in the render today; kept for the density-referred work, MOV-101.
    public let printDmin: Double
    public let printRange: Double
    /// Richards shape of the print curve (1 = symmetric logistic). Below 1 the highlight toe
    /// is shorter and sharper: whites arrive cleanly and bright colors keep their chroma
    /// longer instead of being squeezed together over many stops.
    public let printShape: Double
    /// Unwanted absorptions of the print dyes (density cross-contamination), rows sum to 1.
    public let printDyes: simd_double3x3

    /// Highlight chroma retention (the one non-physical step). Per-layer shoulders flatten
    /// bright saturated light (neon, stage lights) far faster than its brightness warrants;
    /// above +1.5 stops on the brightest channel the result blends toward a ratio-preserving
    /// rendering through the same neutral response. Below +1.5 stops the result is unchanged.
    /// Artistic, not physical: bright neutrals lose part of their printer-light timing, and very
    /// bright saturated colors keep a tint instead of reaching white (MOV-99).
    public let highlightChromaRetention: Double

    /// Scene mid-gray (18%) is timed to this display-linear value on every channel.
    public let middleGrayOut: Double

    /// Printer lights (log10 print exposure per channel) solved for a neutral mid-gray.
    public private(set) var printerLights = SIMD3<Double>(repeating: 0)

    /// Validates `stock` and times the print for it. Throws `EmulsionError.invalidStock`
    /// when a parameter is out of range or the printer lights can't time mid-gray.
    public init(stock: FilmStock) throws(EmulsionError) {
        try Self.validate(stock)
        sensitivity = stock.negative.sensitivity
        negativeGamma = stock.negative.gamma
        negativeRange = stock.negative.densityRange
        negativeOffset = stock.negative.exposureOffset
        printGamma = stock.print.gamma
        printDmin = stock.print.minimumDensity
        printRange = stock.print.densityRange
        printShape = stock.print.shape
        printDyes = stock.print.dyes
        highlightChromaRetention = stock.rendering.highlightChromaRetention
        middleGrayOut = stock.rendering.middleGrayOut
        calibrate()
        try validateCalibration()
    }

    // MARK: Equations

    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// One layer's characteristic curve: log10 exposure (relative to mid-gray) → negative density.
    package static func negativeDensity(logExposure: Double, gamma: Double, densityRange: Double, exposureOffset: Double) -> Double {
        densityRange * logistic(4 * gamma / densityRange * (logExposure - exposureOffset))
    }

    /// log10 scene exposure (per layer, relative to mid-gray) → negative density.
    public func negativeDensity(_ logE: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            (0..<3).map {
                Self.negativeDensity(
                    logExposure: logE[$0], gamma: negativeGamma[$0], densityRange: negativeRange, exposureOffset: negativeOffset[$0])
            })
    }

    /// log10 print exposure → print density (before dye cross-absorption).
    public func printDensity(_ logP: SIMD3<Double>) -> SIMD3<Double> {
        let k = 4 * printGamma / printRange
        return SIMD3((0..<3).map { printDmin + printRange * pow(Self.logistic(k[$0] * logP[$0]), 1 / printShape) })
    }

    /// Scene-linear Display P3 → display-linear Display P3 (before gamut mapping).
    /// `lights` adds user printer lights (log10) to the calibrated ones.
    public func render(_ scene: SIMD3<Double>, lights: SIMD3<Double> = .zero, saturation: Double = 1) -> SIMD3<Double> {
        render(scene, lights: lights, saturation: saturation, grain: .zero)
    }

    /// `render` with halation and grain, as the film kernels apply them. `glow` is the halation glow
    /// at the exposure of `scene` (the kernels' G·2^EV) and `k` the light returned per layer: each
    /// layer is exposed to `Halation.exposureWithHalation`, and highlight chroma retention sees the
    /// light with that change. `grain` is density added to the negative layers (the neutral response
    /// of highlight chroma retention gets it too).
    func render(
        _ scene: SIMD3<Double>, lights: SIMD3<Double> = .zero, saturation: Double = 1, glow: SIMD3<Double> = .zero,
        layerReturn k: SIMD3<Double> = .zero, grain: SIMD3<Double>
    ) -> SIMD3<Double> {
        let light = saturated(scene, saturation)
        let exposure = simd_max(sensitivity * light, .zero)
        let halated = Halation.exposureWithHalation(exposure, glow: simd_max(glow, .zero), layerReturn: k)
        // The light the layers see, with the halation's change of exposure (for chroma retention).
        let s = light + sensitivity.inverse * (halated - exposure)
        let perLayer = system(logExposure: Self.logExposure(halated), lights: lights, grain: grain)
        let m = max(s.max(), 1e-7)
        let w = highlightChromaRetention * Self.smoothstep(1.5, 4.0, log2(m / 0.18))
        guard w > 0 else { return perLayer }
        let neutral = system(logExposure: layerLogExposure(SIMD3(repeating: m)), lights: lights, grain: grain)
        let ratioPreserving = s * (neutral.y / m)
        return perLayer + (ratioPreserving - perLayer) * w
    }

    /// Display P3 luminance weights (the Color control saturates about this luminance).
    static let p3Luminance = SIMD3<Double>(0.2289746, 0.6917385, 0.0792869)

    func saturated(_ scene: SIMD3<Double>, _ saturation: Double) -> SIMD3<Double> {
        let y = dot(scene, Self.p3Luminance)
        return SIMD3(repeating: y) + (scene - SIMD3(repeating: y)) * saturation
    }

    /// log10 of layer exposure `exposure` relative to mid-gray.
    static func logExposure(_ exposure: SIMD3<Double>) -> SIMD3<Double> {
        let clamped = simd_max(exposure, SIMD3(repeating: 1e-7))
        return SIMD3((0..<3).map { log10(clamped[$0] / 0.18) })
    }

    /// The layers' log10 exposure relative to mid-gray for scene light `scene` (what grain is indexed by).
    func layerLogExposure(_ scene: SIMD3<Double>) -> SIMD3<Double> { Self.logExposure(sensitivity * scene) }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// The photochemical chain from the layers' log exposure; `grain` is density added to the
    /// negative layers.
    func system(logExposure: SIMD3<Double>, lights: SIMD3<Double>, grain: SIMD3<Double> = .zero) -> SIMD3<Double> {
        let dNeg = negativeDensity(logExposure) + grain
        // More negative density → less light reaches the print.
        let logP = printerLights + lights - dNeg
        let dPrint = printDyes * printDensity(logP)
        let paper = printDyes * SIMD3(repeating: printDmin)
        return SIMD3((0..<3).map { pow(10, -(dPrint[$0] - paper[$0])) })
    }

    /// Bisection range for each printer light, in log10 print exposure: far wider than any printable timing.
    private static let printerLightBracket = 4.0

    /// Time the print: solve printer lights so 18% gray prints neutral at `middleGrayOut`.
    /// Dye cross-absorption couples channels, so iterate the per-channel solves.
    private mutating func calibrate() {
        printerLights = .zero
        for _ in 0..<8 {
            for c in 0..<3 {
                var lo = -Self.printerLightBracket
                var hi = Self.printerLightBracket
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

// MARK: Validation

extension FilmModel {
    /// How far a sensitivity or dye row sum may stray from 1 (rounding in the stock file).
    private static let rowSumTolerance = 1e-6
    /// How close the calibrated print must time mid-gray to `middleGrayOut`.
    private static let calibrationTolerance = 1e-6

    private static func validate(_ stock: FilmStock) throws(EmulsionError) {
        let negative = stock.negative
        let print = stock.print
        let rendering = stock.rendering
        let numbers =
            (negative.sensitivity.rows + print.dyes.rows + [negative.gamma, negative.exposureOffset, print.gamma])
            .flatMap { [$0.x, $0.y, $0.z] }
            + [
                negative.densityRange, print.minimumDensity, print.densityRange, print.shape,
                rendering.highlightChromaRetention, rendering.middleGrayOut,
            ]
        try require(numbers.allSatisfy(\.isFinite), "every parameter must be a finite number.")
        try require(negative.gamma.min() > 0, "negative gamma must be above 0.")
        try require(print.gamma.min() > 0, "print gamma must be above 0.")
        try require(negative.densityRange > 0, "negative density range must be above 0.")
        try require(print.densityRange > 0, "print density range must be above 0.")
        try require(print.shape > 0, "print shape must be above 0.")
        try require(print.minimumDensity >= 0, "print minimum density can't be negative.")
        try require(rendering.middleGrayOut > 0 && rendering.middleGrayOut < 1, "middle gray out must be between 0 and 1.")
        try require(
            (0...1).contains(rendering.highlightChromaRetention), "highlight chroma retention must be between 0 and 1.")
        try requireRowsSumToOne(negative.sensitivity, "sensitivity")
        try requireRowsSumToOne(print.dyes, "print dye")
    }

    /// Rows summing to 1 is what keeps neutral light neutral through the matrix.
    private static func requireRowsSumToOne(_ m: simd_double3x3, _ name: String) throws(EmulsionError) {
        let sums = m.rows.map { $0.x + $0.y + $0.z }
        try require(
            sums.allSatisfy { abs($0 - 1) <= rowSumTolerance },
            "each \(name) matrix row must sum to 1 so neutrals stay neutral (row sums \(sums)).")
    }

    private func validateCalibration() throws(EmulsionError) {
        let midGray = render(SIMD3(repeating: 0.18))
        let timed = (0..<3).allSatisfy { abs(midGray[$0] - middleGrayOut) <= Self.calibrationTolerance }
        try Self.require(
            timed,
            "the printer lights can't time mid-gray to \(middleGrayOut) (mid-gray prints at \(midGray), lights \(printerLights)).")
    }

    private static func require(_ condition: Bool, _ reason: String) throws(EmulsionError) {
        guard condition else { throw .invalidStock(reason) }
    }
}
