import Foundation

/// A camera negative's dye set, from its datasheet's spectral dye density chart, on a wavelength grid.
///
/// The sheet's cyan, magenta and yellow curves are "D-mins subtracted" and peak-normalized: each is the net spectral
/// density change per unit of dye formed, already including the colored masking coupler that forming the dye consumes
/// (why magenta dips below zero near 445 nm, FILM-THEORY §3.3). `minimumDensity` is base + fog + the unused masking
/// couplers (the orange mask). For dye amounts c = (cyan, magenta, yellow):
///
///     D(λ) = Dmin(λ) + Σ_k c_k·ε_k(λ)
///
/// Between traced samples the curves are interpolated linearly; outside a curve's traced span its end value is held
/// (an assumption: the sheet doesn't draw there; `NegativeDyeSetReport` reports how much zero-filling the dyes instead
/// changes the results).
struct NegativeDyeSet: Sendable, Equatable {
    enum Dye: String, CaseIterable, Codable, Sendable { case cyan, magenta, yellow }

    /// Newton has converged when every channel's density misses its target by at most this, in D.
    static let convergenceTolerance = 1e-10
    /// Newton converges quadratically from the previous neutral-scale sample's amounts in a handful of steps.
    static let iterationLimit = 50

    let wavelengths: [Double]
    let minimumDensity: [Double]
    /// ε_k(λ): cyan, magenta, yellow.
    let dyes: [[Double]]

    init(wavelengths: [Double], minimumDensity: [Double], dyes: [[Double]]) {
        self.wavelengths = wavelengths
        self.minimumDensity = minimumDensity
        self.dyes = dyes
    }

    /// - Parameter dyeEdge: how the dye curves continue outside their traced spans; the minimum density always holds.
    init(chart: DigitizedChart, stock: String, grid: [Double] = SpectralResponsivities.grid, dyeEdge: DigitizedCurve.Edge = .hold)
        throws(DyeSetError)
    {
        func curve(_ name: String) throws(DyeSetError) -> DigitizedCurve {
            guard let curve = chart.curve(named: name) else { throw .missingCurve(stock: stock, curve: name) }
            return curve
        }
        var dyes: [[Double]] = []
        for dye in Dye.allCases { dyes.append(try curve(dye.rawValue).resampled(onto: grid, edge: dyeEdge)) }
        self.init(
            wavelengths: grid, minimumDensity: try curve(DyeSumCheck.minimumDensity).resampled(onto: grid, edge: .hold), dyes: dyes)
    }

    func spectralDensity(_ amounts: [Double]) -> [Double] {
        minimumDensity.indices.map { i in minimumDensity[i] + zip(amounts, dyes).reduce(0) { $0 + $1.0 * $1.1[i] } }
    }

    /// This dye set read through `responsivities`.
    func densitometer(_ responsivities: SpectralResponsivities) -> Densitometer {
        Densitometer(dyeSet: self, responsivities: responsivities)
    }

    /// The dye set read through one set of responsivities, with the minimum density's integral densities computed once.
    struct Densitometer: Sendable {
        let dyeSet: NegativeDyeSet
        let responsivities: SpectralResponsivities
        /// D_Π(0) per channel (red, green, blue).
        let minimumDensities: [Double]

        init(dyeSet: NegativeDyeSet, responsivities: SpectralResponsivities) {
            self.dyeSet = dyeSet
            self.responsivities = responsivities
            minimumDensities = responsivities.densities(of: dyeSet.minimumDensity)
        }

        /// D_Π(c) − D_Π(0) per channel (red, green, blue).
        func densityAboveMinimum(_ amounts: [Double]) -> [Double] {
            densityAboveMinimum(spectralDensity: dyeSet.spectralDensity(amounts))
        }

        /// ∂D_i/∂c_k = Σ Π_i T ε_k / Σ Π_i T, with T the transmittance at `amounts`. Rows are channels, columns dyes.
        func jacobian(_ amounts: [Double]) -> [[Double]] { jacobian(spectralDensity: dyeSet.spectralDensity(amounts)) }

        /// The dye amounts whose density above minimum is `target`, by Newton's method with the analytic Jacobian (each
        /// step solves JᵀJ δ = −Jᵀr, the Newton step for a square, nonsingular J). The spectral density is computed once
        /// per step, for both the residual and the Jacobian.
        func amounts(forDensityAboveMinimum target: [Double], from start: [Double]) throws(DyeSetError) -> [Double] {
            var amounts = start
            var steps = 0
            while true {
                let density = dyeSet.spectralDensity(amounts)
                let residual = zip(densityAboveMinimum(spectralDensity: density), target).map { $0 - $1 }
                if residual.maxAbs <= NegativeDyeSet.convergenceTolerance { return amounts }
                guard steps < NegativeDyeSet.iterationLimit,
                    let step = NormalEquations.solveLeastSquares(columns: jacobianColumns(density), rhs: residual.map { -$0 })
                else { throw .dyeAmountsDidNotConverge(target: target, residual: residual.maxAbs) }
                amounts = zip(amounts, step).map { $0 + $1 }
                steps += 1
            }
        }

        private func densityAboveMinimum(spectralDensity: [Double]) -> [Double] {
            zip(responsivities.densities(of: spectralDensity), minimumDensities).map { $0 - $1 }
        }

        /// The Jacobian's columns: one per dye, over the channels.
        private func jacobianColumns(_ spectralDensity: [Double]) -> [[Double]] {
            let j = jacobian(spectralDensity: spectralDensity)
            return dyeSet.dyes.indices.map { k in j.map { $0[k] } }
        }

        private func jacobian(spectralDensity: [Double]) -> [[Double]] {
            let transmittance = spectralDensity.map { pow(10, -$0) }
            return responsivities.channels.map { weights in
                let weighted = zip(weights, transmittance).map { $0 * $1 }
                let total = weighted.reduce(0, +)
                return dyeSet.dyes.map { weighted.dot($0) / total }
            }
        }
    }
}
