import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// The negative stage: characteristic curves in dye amount, and printing density through the dye matrix.
struct NegativeTests {
    /// Narrow toe and shoulder far apart, so the curve between them is a straight line to rounding.
    static let curve = (gamma: 0.55, toe: -1.5, toeWidth: 0.05, shoulder: 2.0, shoulderWidth: 0.05)

    static func dyeAmount(_ x: Double) -> Double {
        FilmModel.negativeDyeAmount(
            logExposure: x, gamma: curve.gamma, toeExposure: curve.toe, toeWidth: curve.toeWidth, shoulderExposure: curve.shoulder,
            shoulderWidth: curve.shoulderWidth)
    }

    static func slope(_ f: (Double) -> Double, at x: Double) -> Double {
        let step = 1e-4
        return (f(x + step) - f(x - step)) / (2 * step)
    }

    @Test func slopeIsGammaBetweenNarrowToeAndShoulder() {
        let middle = (Self.curve.toe + Self.curve.shoulder) / 2
        #expect(abs(Self.slope(Self.dyeAmount, at: middle) - Self.curve.gamma) < 1e-6)
    }

    /// With the fitted widths the bends still pull on the midpoint: measured 0.987 / 0.996 / 0.993 of gamma (R, G, B);
    /// red's wide shoulder costs most.
    @Test func defaultSlopeMidwayIsNearlyGamma() {
        let model = FilmLook.stock
        for c in 0..<3 {
            let middle = (model.negativeToeExposure[c] + model.negativeShoulderExposure[c]) / 2
            let slope = Self.slope(
                { x in
                    FilmModel.negativeDyeAmount(
                        logExposure: x, gamma: model.negativeGamma[c], toeExposure: model.negativeToeExposure[c],
                        toeWidth: model.negativeToeWidth[c], shoulderExposure: model.negativeShoulderExposure[c],
                        shoulderWidth: model.negativeShoulderWidth[c])
                }, at: middle)
            #expect(abs(slope / model.negativeGamma[c] - 1) < 0.02, "layer \(c): \(slope / model.negativeGamma[c])")
        }
    }

    @Test func curveRunsFromZeroToItsPlateau() {
        let below = Self.curve.toe - 30 * Self.curve.toeWidth
        let above = Self.curve.shoulder + 30 * Self.curve.shoulderWidth
        #expect(abs(Self.dyeAmount(below)) < 1e-9)
        #expect(abs(Self.dyeAmount(above) - Self.curve.gamma * (Self.curve.shoulder - Self.curve.toe)) < 1e-9)
    }

    /// The stable softplus doesn't overflow far above zero; far below, it keeps small positive values down to about −36.7
    /// and is exactly 0 beyond (never negative or NaN).
    @Test func softplusStaysFiniteAtExtremes() {
        #expect(FilmModel.softplus(1000) == 1000)
        #expect(FilmModel.softplus(-1000) == 0)
        #expect(abs(FilmModel.softplus(0) - log(2)) < 1e-15)
        #expect(FilmModel.softplus(-30) > 0 && FilmModel.softplus(-30) < 1e-12)
        #expect(FilmModel.softplus(-36) > 0 && FilmModel.softplus(-38) == 0)
    }

    @Test func defaultNegativeIsMonotoneFromMinusToPlusEightStops() {
        let model = FilmLook.stock
        var previousAmounts = SIMD3<Double>(repeating: -.infinity)
        var previousDensity = SIMD3<Double>(repeating: -.infinity)
        for stops in stride(from: -8.0, through: 8.0, by: 0.1) {
            let logE = SIMD3(repeating: stops * log10(2))
            let amounts = model.negativeDyeAmount(logE)
            let density = model.negativePrintingDensity(logE)
            #expect(all(amounts .> previousAmounts) && all(density .> previousDensity), "at \(stops) stops")
            previousAmounts = amounts
            previousDensity = density
        }
    }

    /// The matrix's positive cross terms add printing density to the other channels in proportion to each dye, so a
    /// saturated color's channels separate less on the print than with an identity matrix (print contrast rebalanced
    /// so the gray scale is the same).
    @Test(arguments: [SIMD3(0.30, 0.04, 0.03), SIMD3(0.03, 0.25, 0.04), SIMD3(0.03, 0.05, 0.30)])
    func printingDensityCrossTermsLowerChroma(_ scene: SIMD3<Double>) throws {
        var identity = try FilmStock.bundled(named: "emulsion-default")
        let systemContrast = identity.systemContrast.y
        identity.negative.printingDensity = matrix_identity_double3x3
        identity.rebalancePrintGamma(systemContrast: systemContrast)
        let withoutCrossTerms = try FilmModel(stock: identity)
        func chroma(_ model: FilmModel) -> Double { Fixtures.chroma(EmulsionTestCase.p3ToLab(model.render(scene))) }
        #expect(chroma(FilmLook.stock) < 0.97 * chroma(withoutCrossTerms))
    }
}
