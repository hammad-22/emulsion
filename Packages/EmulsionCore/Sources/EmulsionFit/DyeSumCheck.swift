/// Do the dye spectra add up to the neutral? A data check, not an engine one (MOV-17; docs).
struct DyeSumCheck: Sendable, Equatable {
    /// MOV-17 acceptance: largest |residual|, density.
    static let targetMaxResidual = 0.05
    static let dyes = ["yellow", "magenta", "cyan"]
    static let neutrals = ["midscale_neutral", "visual_neutral"]
    static let minimumDensity = "minimum_density"
    /// Below 400 nm the print film's neutral rises steeply above the dye sum.
    static let imageDyeWavelengths = 400.0...700.0

    struct Comparison: Sendable, Equatable {
        var subtractsMinimumDensity = false
        var wavelengths: ClosedRange<Double>?
        /// nil: fit non-negative scales.
        var fixedScales: [Double]?
        /// nil: every drawn wavelength; otherwise multiples of this step, nm.
        var wavelengthStep: Double?
    }

    let comparison: Comparison
    let neutral: String
    /// Yellow, magenta, cyan.
    let scales: [Double]
    let wavelengths: [Double]
    /// Neutral (less minimum density, when subtracted) minus the scaled dye sum.
    let residuals: [Double]

    var rms: Double { residuals.rms }
    var meanResidual: Double { residuals.reduce(0, +) / Double(residuals.count) }
    var maxAbsResidual: Double { residuals.maxAbs }
    var wavelengthOfMax: Double {
        residuals.indices.max { abs(residuals[$0]) < abs(residuals[$1]) }.map { wavelengths[$0] } ?? .nan
    }
    var meetsTarget: Bool { maxAbsResidual <= Self.targetMaxResidual }

    static func acceptance(_ chart: DigitizedChart, filmType: StockManifest.FilmType) -> DyeSumCheck? {
        let comparison =
            switch filmType {
            case .cameraNegative: Comparison(subtractsMinimumDensity: true)
            case .printFilm: Comparison(wavelengths: imageDyeWavelengths)
            }
        return compared(chart, comparison)
    }

    /// Reported, never asserted, beside the acceptance row.
    static func diagnostics(_ chart: DigitizedChart, filmType: StockManifest.FilmType) -> [(label: String, check: DyeSumCheck)] {
        let comparisons: [(String, Comparison)] =
            switch filmType {
            case .cameraNegative: [("neutral, Dmin kept", Comparison())]
            case .printFilm:
                [
                    ("full overlap", Comparison()),
                    ("scales = 1, 400–700", Comparison(wavelengths: imageDyeWavelengths, fixedScales: [1, 1, 1])),
                ]
            }
        return comparisons.compactMap { label, comparison in compared(chart, comparison).map { (label, $0) } }
    }

    static func compared(_ chart: DigitizedChart, _ comparison: Comparison) -> DyeSumCheck? {
        guard let samples = samples(chart, comparison) else { return nil }
        guard let scales = comparison.fixedScales ?? bestNonNegativeScales(samples) else { return nil }
        return DyeSumCheck(
            comparison: comparison, neutral: samples.neutralName, scales: scales, wavelengths: samples.wavelengths,
            residuals: residuals(samples, scales))
    }

    /// Exact: the convex optimum is the unconstrained fit on some subset of the three dyes.
    private static func bestNonNegativeScales(_ samples: Samples) -> [Double]? {
        var best: (scales: [Double], cost: Double)?
        for subset in 0..<(1 << dyes.count) {
            let active = dyes.indices.filter { subset & (1 << $0) != 0 }
            var scales = [Double](repeating: 0, count: dyes.count)
            if !active.isEmpty {
                guard
                    let solution = NormalEquations.solveLeastSquares(
                        columns: active.map { samples.dyes[$0] }, rhs: samples.neutral),
                    solution.allSatisfy({ $0 >= 0 })
                else { continue }
                for (index, value) in zip(active, solution) { scales[index] = value }
            }
            let cost = residuals(samples, scales).sumOfSquares
            if best.map({ cost < $0.cost }) ?? true { best = (scales, cost) }
        }
        return best?.scales
    }

    private struct Samples {
        let neutralName: String
        let wavelengths: [Double]
        let dyes: [[Double]]
        let neutral: [Double]
    }

    private static func samples(_ chart: DigitizedChart, _ comparison: Comparison) -> Samples? {
        guard let neutralName = neutrals.first(where: { chart.curve(named: $0) != nil }) else { return nil }
        let extra = comparison.subtractsMinimumDensity ? [minimumDensity] : []
        guard let aligned = chart.aligned(dyes + [neutralName] + extra) else { return nil }
        let kept = aligned.x.indices.filter { i in
            (comparison.wavelengths?.contains(aligned.x[i]) ?? true)
                && (comparison.wavelengthStep.map { aligned.x[i].truncatingRemainder(dividingBy: $0) == 0 } ?? true)
        }
        guard !kept.isEmpty else { return nil }
        let neutral = kept.map { i in
            aligned.columns[dyes.count][i] - (comparison.subtractsMinimumDensity ? aligned.columns[dyes.count + 1][i] : 0)
        }
        return Samples(
            neutralName: neutralName, wavelengths: kept.map { aligned.x[$0] },
            dyes: aligned.columns.prefix(dyes.count).map { column in kept.map { column[$0] } }, neutral: neutral)
    }

    private static func residuals(_ samples: Samples, _ scales: [Double]) -> [Double] {
        samples.neutral.indices.map { i in samples.neutral[i] - zip(scales, samples.dyes).reduce(0) { $0 + $1.0 * $1.1[i] } }
    }
}
