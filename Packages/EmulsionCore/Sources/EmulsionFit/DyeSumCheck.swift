/// Do the three dye spectra add up to the sheet's neutral spectrum? Compares a neutral against a_Y·yellow + a_M·magenta
/// + a_C·cyan with non-negative scales (least squares, or fixed) over the wavelengths where every curve used is drawn.
/// A check on the digitized spectra (MOV-17), not on the engine. Dye densities are used as drawn, negative lobes
/// included (the negatives' magenta dye dips below zero near 445 nm).
///
/// Acceptance (`acceptance(_:filmType:)`), target max |residual| ≤ 0.05 D:
/// - Camera negatives: neutral − minimum density against the fitted dye sum. The sheets draw the dye curves "D-mins
///   subtracted" while the neutral and minimum-density spectra are drawn as measured.
/// - Print film: neutral against the fitted dye sum over 400–700 nm.
struct DyeSumCheck: Sendable, Equatable {
    /// MOV-17 acceptance: largest |residual| in density.
    static let targetMaxResidual = 0.05
    static let dyes = ["yellow", "magenta", "cyan"]
    /// Negatives draw a midscale neutral; the print film draws a visual neutral.
    static let neutrals = ["midscale_neutral", "visual_neutral"]
    /// The negatives' base + mask spectrum.
    static let minimumDensity = "minimum_density"
    /// Where the print film's three image dyes account for its visual neutral; below 400 nm the neutral rises steeply
    /// above the dye sum.
    static let imageDyeWavelengths = 400.0...700.0

    /// What is compared with what.
    struct Comparison: Sendable, Equatable {
        var subtractsMinimumDensity = false
        /// nil: every wavelength where all curves used are drawn.
        var wavelengths: ClosedRange<Double>?
        /// nil: fit non-negative scales; otherwise use these.
        var fixedScales: [Double]?
    }

    let comparison: Comparison
    let neutral: String
    /// a_Y, a_M, a_C.
    let scales: [Double]
    let wavelengths: [Double]
    /// Neutral (less minimum density, when subtracted) minus the scaled dye sum, per wavelength.
    let residuals: [Double]

    var rms: Double { residuals.rms }
    var meanResidual: Double { residuals.reduce(0, +) / Double(residuals.count) }
    var maxAbsResidual: Double { residuals.map(abs).max() ?? 0 }
    var wavelengthOfMax: Double {
        residuals.indices.max { abs(residuals[$0]) < abs(residuals[$1]) }.map { wavelengths[$0] } ?? .nan
    }
    var meetsTarget: Bool { maxAbsResidual <= Self.targetMaxResidual }

    /// The MOV-17 acceptance comparison for this chart.
    static func acceptance(_ chart: DigitizedChart, filmType: StockManifest.FilmType) -> DyeSumCheck? {
        let comparison =
            switch filmType {
            case .cameraNegative: Comparison(subtractsMinimumDensity: true)
            case .printFilm: Comparison(wavelengths: imageDyeWavelengths)
            }
        return compared(chart, comparison)
    }

    /// Reported alongside the acceptance row, never asserted: the plain neutral for negatives; the full overlap and
    /// the scales-fixed-to-1 sum (the sheet says its dyes are normalized to the visual neutral) for the print film.
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

    /// With three dyes every active set can be tried: the optimum of this convex problem is the unconstrained fit on
    /// some subset of dyes, so the best non-negative subset fit is exact.
    private static func bestNonNegativeScales(_ samples: Samples) -> [Double]? {
        var best: (scales: [Double], cost: Double)?
        for subset in 0..<(1 << dyes.count) {
            let active = dyes.indices.filter { subset & (1 << $0) != 0 }
            var scales = [Double](repeating: 0, count: dyes.count)
            if !active.isEmpty {
                let columns = active.map { samples.dyes[$0] }
                let a = columns.flatMap { c in columns.map { c.dot($0) } }
                guard let solution = NormalEquations.solve(a, columns.map { $0.dot(samples.neutral) }),
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
        let kept = aligned.x.indices.filter { comparison.wavelengths?.contains(aligned.x[$0]) ?? true }
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
