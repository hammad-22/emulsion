/// A linear conversion to printing density above minimum density, fitted by least squares, with its residuals
/// (printing density − fitted) reported per channel on the neutral scale and on a lattice of dye amounts.
///
/// - `dyeAmounts`, PD ≈ P·c: printing density per unit dye.
/// - `dyeAmountsWithOffset`, PD ≈ P·c + b: the form the engine uses (`NegativeDyeSetReport.ConversionSet.engine`), with
///   the neutral scale weighted by `engineNeutralScaleWeight`. The offset costs nothing in the engine: the calibrated
///   printer lights absorb it.
/// - `statusM`, PD ≈ M·SM, and `statusMWithOffset`, PD ≈ M·SM + b: whether a 3×3 (plus offset) from Status M
///   suffices, as ST 2065-2 NOTE 3 and RP 180 §3 suggest (FILM-THEORY gap G-1).
struct PrintingDensityConversion: Codable, Sendable, Equatable {
    enum Model: String, CaseIterable, Codable, Sendable {
        case dyeAmounts, dyeAmountsWithOffset, statusM, statusMWithOffset

        var formula: String {
            switch self {
            case .dyeAmounts: "PD = P·c"
            case .dyeAmountsWithOffset: "PD = P·c + b"
            case .statusM: "PD = M·SM"
            case .statusMWithOffset: "PD = M·SM + b"
            }
        }

        func inputs(_ point: Point) -> [Double] {
            switch self {
            case .dyeAmounts: point.dyeAmounts
            case .dyeAmountsWithOffset: point.dyeAmounts + [1]
            case .statusM: point.statusM
            case .statusMWithOffset: point.statusM + [1]
            }
        }

        var hasOffset: Bool { self == .dyeAmountsWithOffset || self == .statusMWithOffset }
    }

    /// One sample: dye amounts (cyan, magenta, yellow) and the Status M and printing densities above minimum they give.
    struct Point: Sendable, Equatable {
        let dyeAmounts: [Double]
        let statusM: [Double]
        let printingDensity: [Double]
    }

    /// Per printing-density channel (red, green, blue).
    struct Residuals: Codable, Sendable, Equatable {
        let sampleCount: Int
        let rms: [Double]
        let maxAbs: [Double]
    }

    /// Which samples a fit is fitted on; residuals are always reported on both.
    enum FitSet: String, Codable, Sendable {
        /// Colors as well as neutrals: what a conversion applied to every pixel needs.
        case neutralScaleAndLattice
        /// Neutrals only: how closely a 3×3 can follow the neutral scale alone.
        case neutralScale
    }

    /// Lattice points per dye axis.
    static let latticeSteps = 9
    /// The engine's matrix multiplies each neutral-scale row of the fit by this (lattice rows by 1). The neutral scale
    /// sets tone and gray balance, so it should be followed closely. For 250D APD, at 10 the neutral-scale max residual
    /// falls to about 0.006 D (0.017 unweighted) while the lattice RMS rises by at most 0.004 D; at 100 the lattice
    /// residuals grow several-fold for a further 0.002 D on neutrals.
    static let engineNeutralScaleWeight = 10.0
    /// The engine-matrix weights the reports compare.
    static let neutralScaleWeightSweep = [1.0, engineNeutralScaleWeight, 100.0]

    let model: Model
    let fittedOn: FitSet
    /// Each neutral-scale row of the fit is multiplied by this; lattice rows by 1. Residuals are unweighted.
    let neutralScaleWeight: Double
    /// Rows: printing density red, green, blue. Columns: cyan, magenta, yellow amounts, or Status M red, green, blue.
    let matrix: [[Double]]
    let offset: [Double]?
    let neutralScale: Residuals
    let lattice: Residuals

    var formula: String { model.formula }

    /// - Parameter neutralScaleWeight: multiplies each neutral-scale row (squared weight w² in the normal equations).
    static func fit(
        _ model: Model, on fitSet: FitSet = .neutralScaleAndLattice, neutralScaleWeight: Double = 1, neutralScale: [Point],
        lattice: [Point]
    ) throws(DyeSetError) -> PrintingDensityConversion {
        let points = fitSet == .neutralScale ? neutralScale : neutralScale + lattice
        let squaredWeights = points.indices.map { $0 < neutralScale.count ? neutralScaleWeight * neutralScaleWeight : 1 }
        let inputs = points.map(model.inputs)
        let columns = (inputs.first ?? []).indices.map { i in inputs.map { $0[i] } }
        var rows: [[Double]] = []
        for channel in SpectralResponsivities.Channel.allCases.indices {
            guard
                let row = NormalEquations.solveLeastSquares(
                    columns: columns, rhs: points.map { $0.printingDensity[channel] }, weights: squaredWeights)
            else { throw .singularFit(model.formula) }
            rows.append(row)
        }
        func residuals(_ points: [Point]) -> Residuals {
            let perChannel = rows.indices.map { channel in
                points.map { $0.printingDensity[channel] - rows[channel].dot(model.inputs($0)) }
            }
            return Residuals(sampleCount: points.count, rms: perChannel.map(\.rms), maxAbs: perChannel.map(\.maxAbs))
        }
        return PrintingDensityConversion(
            model: model, fittedOn: fitSet, neutralScaleWeight: neutralScaleWeight,
            matrix: rows.map { Array($0.prefix(3)) }, offset: model.hasOffset ? rows.map { $0[3] } : nil,
            neutralScale: residuals(neutralScale),
            lattice: residuals(lattice))
    }

    /// Every combination of `latticeSteps` evenly spaced amounts from 0 to each dye's maximum, cyan slowest.
    static func lattice(maxAmounts: [Double]) -> [[Double]] {
        let fractions = (0..<latticeSteps).map { Double($0) / Double(latticeSteps - 1) }
        return fractions.flatMap { c in fractions.flatMap { m in fractions.map { y in zip([c, m, y], maxAmounts).map { $0 * $1 } } } }
    }
}

extension PrintingDensityConversion.Point {
    /// The Status M and printing densities above minimum that `dyeAmounts` give, read through the dye set's densitometers.
    init(
        dyeAmounts: [Double], statusM: NegativeDyeSet.Densitometer, printingDensity: NegativeDyeSet.Densitometer
    ) {
        self.init(
            dyeAmounts: dyeAmounts, statusM: statusM.densityAboveMinimum(dyeAmounts),
            printingDensity: printingDensity.densityAboveMinimum(dyeAmounts))
    }
}
