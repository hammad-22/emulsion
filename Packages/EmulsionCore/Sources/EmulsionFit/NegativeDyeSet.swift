import Foundation

/// A camera negative's dye set: D(λ) = Dmin(λ) + Σ c_k·ε_k(λ) (docs/CONSTANTS.md).
struct NegativeDyeSet: Sendable, Equatable {
    enum Dye: String, CaseIterable, Codable, Sendable { case cyan, magenta, yellow }

    /// Newton tolerance, density, and step limit (it converges in a handful from the last sample).
    static let convergenceTolerance = 1e-10
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

    /// How the dye curves continue outside their traced spans; the minimum density always holds.
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

    func densitometer(_ responsivities: SpectralResponsivities) -> Densitometer {
        Densitometer(dyeSet: self, responsivities: responsivities)
    }

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

        func densityAboveMinimum(_ amounts: [Double]) -> [Double] {
            densityAboveMinimum(spectralDensity: dyeSet.spectralDensity(amounts))
        }

        /// ∂D_i/∂c_k = Σ Π_i T ε_k / Σ Π_i T. Rows are channels, columns dyes.
        func jacobian(_ amounts: [Double]) -> [[Double]] { jacobian(spectralDensity: dyeSet.spectralDensity(amounts)) }

        /// Newton's method with the analytic Jacobian (JᵀJ δ = −Jᵀr, exact for a square J).
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
