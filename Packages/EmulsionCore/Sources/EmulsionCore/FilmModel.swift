import Foundation
import simd

/// Emulsion's look as a photochemical system rather than a curve or LUT:
///
///   scene light ─▶ negative layers (sensitivity crosstalk) ─▶ characteristic curves → dye amounts
///               ─▶ printing density (dye amounts through the printing-density matrix)
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

    /// Negative characteristic curves, per layer (red-, green-, blue-sensitive), as dye amount above
    /// minimum density against log10 exposure x relative to mid-gray (`negativeDyeAmount`): zero far
    /// below the toe, a straight line of slope `negativeGamma` between toe and shoulder, flat far above
    /// the shoulder. A toe-and-shoulder form fitted to datasheet dye amounts (Approximated; see
    /// docs/ENGINE.md, "Fitting stocks", for how closely it follows them).
    public let negativeGamma: SIMD3<Double>
    public let negativeToeExposure: SIMD3<Double>
    public let negativeToeWidth: SIMD3<Double>
    public let negativeShoulderExposure: SIMD3<Double>
    public let negativeShoulderWidth: SIMD3<Double>
    /// Printing density per unit dye: rows printing density R, G, B; columns the cyan, magenta and
    /// yellow amounts of the red-, green- and blue-sensitive layers. Its cross terms are the dyes'
    /// unwanted absorptions net of the masking couplers, as the print stock sees them.
    public let printingDensity: simd_double3x3

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
        negativeToeExposure = stock.negative.toeExposure
        negativeToeWidth = stock.negative.toeWidth
        negativeShoulderExposure = stock.negative.shoulderExposure
        negativeShoulderWidth = stock.negative.shoulderWidth
        printingDensity = stock.negative.printingDensity
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

    /// log(1 + eˣ) in a form that doesn't overflow far above zero. Far below zero it returns exactly 0 once e⁻|ˣ| is
    /// under machine epsilon (x below about −36.7 here, −16.6 in the Float kernel).
    static func softplus(_ x: Double) -> Double { max(x, 0) + log(1 + exp(-abs(x))) }

    /// One layer's characteristic curve: log10 exposure (relative to mid-gray) → dye amount above minimum density.
    package static func negativeDyeAmount(
        logExposure: Double, gamma: Double, toeExposure: Double, toeWidth: Double, shoulderExposure: Double, shoulderWidth: Double
    ) -> Double {
        gamma
            * (toeWidth * softplus((logExposure - toeExposure) / toeWidth)
                - shoulderWidth * softplus((logExposure - shoulderExposure) / shoulderWidth))
    }

    /// log10 scene exposure (per layer, relative to mid-gray) → dye amounts (cyan, magenta, yellow).
    public func negativeDyeAmount(_ logE: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            (0..<3).map {
                Self.negativeDyeAmount(
                    logExposure: logE[$0], gamma: negativeGamma[$0], toeExposure: negativeToeExposure[$0],
                    toeWidth: negativeToeWidth[$0], shoulderExposure: negativeShoulderExposure[$0],
                    shoulderWidth: negativeShoulderWidth[$0])
            })
    }

    /// log10 scene exposure (per layer, relative to mid-gray) → printing density above minimum density.
    public func negativePrintingDensity(_ logE: SIMD3<Double>) -> SIMD3<Double> { printingDensity * negativeDyeAmount(logE) }

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

    /// The smallest layer exposure (scene-linear) the chain uses: black and the exposures the sensitivity crosstalk drives
    /// negative are clamped to it, so log10 stays finite. The kernel clamps to the same 1e-7 (`filmRender`, `filmSystemRelative`).
    static let layerExposureFloor = 1e-7
    /// The lowest log10 exposure relative to mid-gray a layer can see: `layerExposureFloor` (about −20.8 stops).
    static let minimumLogExposure = log10(layerExposureFloor / 0.18)
    /// The highest log10 exposure relative to mid-gray a stock must stay well behaved to: +6 (about +20 stops), beyond any
    /// exposure the pipeline produces (scene values above mid-gray plus the largest exposure edit).
    static let maximumLogExposure = 6.0

    /// The photochemical chain itself.
    func system(_ s: SIMD3<Double>, lights: SIMD3<Double>) -> SIMD3<Double> {
        let exposure = simd_max(sensitivity * s, SIMD3(repeating: Self.layerExposureFloor))
        let logE = SIMD3((0..<3).map { log10(exposure[$0] / 0.18) })
        let dNeg = negativePrintingDensity(logE)
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
            (negative.sensitivity.rows + negative.printingDensity.rows + print.dyes.rows
            + [
                negative.gamma, negative.toeExposure, negative.toeWidth, negative.shoulderExposure, negative.shoulderWidth,
                print.gamma,
            ])
            .flatMap { [$0.x, $0.y, $0.z] }
            + [print.minimumDensity, print.densityRange, print.shape, rendering.highlightChromaRetention, rendering.middleGrayOut]
        try require(numbers.allSatisfy(\.isFinite), "every parameter must be a finite number.")
        try require(negative.gamma.min() > 0, "negative gamma must be above 0.")
        try require(negative.toeWidth.min() > 0, "negative toe width must be above 0.")
        try require(negative.shoulderWidth.min() > 0, "negative shoulder width must be above 0.")
        try require(
            all(negative.shoulderExposure .> negative.toeExposure), "each negative shoulder exposure must be above its toe exposure.")
        let printingDensity = negative.printingDensity
        try require(
            (0..<3).allSatisfy { printingDensity[$0, $0] > 0 }, "the printing-density matrix must have a positive diagonal.")
        try require(printingDensity.determinant != 0, "the printing-density matrix must be invertible (non-zero determinant).")
        try require(
            negative.printingDensityGamma.min() > 0,
            "each channel's printing density must rise with neutral exposure (printingDensity · gamma is "
                + "\(negative.printingDensityGamma)).")
        try requireRisingNegativeCurves(negative)
        try require(print.gamma.min() > 0, "print gamma must be above 0.")
        try require(print.densityRange > 0, "print density range must be above 0.")
        try require(print.shape > 0, "print shape must be above 0.")
        try require(print.minimumDensity >= 0, "print minimum density can't be negative.")
        try require(rendering.middleGrayOut > 0 && rendering.middleGrayOut < 1, "middle gray out must be between 0 and 1.")
        try require(
            (0...1).contains(rendering.highlightChromaRetention), "highlight chroma retention must be between 0 and 1.")
        try requireRowsSumToOne(negative.sensitivity, "sensitivity")
        try requireRowsSumToOne(print.dyes, "print dye")
    }

    /// Each layer's dye amount must not fall as exposure rises, over every exposure the engine reaches. The curve's slope
    /// is gamma·[σ(z_t) − σ(z_s)], z_t = (x − toeExposure)/toeWidth and z_s = (x − shoulderExposure)/shoulderWidth, so it
    /// is non-negative exactly where z_t ≥ z_s. z_t − z_s is linear in x: checking both ends of the range covers it all.
    private static func requireRisingNegativeCurves(_ negative: FilmStock.Negative) throws(EmulsionError) {
        for (layer, name) in ["red", "green", "blue"].enumerated() {
            let rises = [minimumLogExposure, maximumLogExposure].allSatisfy { x in
                (x - negative.toeExposure[layer]) / negative.toeWidth[layer]
                    >= (x - negative.shoulderExposure[layer]) / negative.shoulderWidth[layer]
            }
            try require(
                rises,
                "the \(name) layer's negative curve must not fall between log10 exposure "
                    + String(format: "%.2f and %+.2f", minimumLogExposure, maximumLogExposure)
                    + " from mid-gray, the range the engine reaches: its shoulder bends down before its toe has risen "
                    + "(toe width \(negative.toeWidth[layer]), shoulder width \(negative.shoulderWidth[layer])).")
        }
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
