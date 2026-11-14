/// A least-squares conversion to printing density above minimum (docs/CONSTANTS.md).
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

    enum FitSet: String, Codable, Sendable {
        case neutralScaleAndLattice
        case neutralScale
    }

    static let latticeSteps = 9
    /// Neutral-scale row weight of the engine fit; measured trade-off on 250D APD (docs).
    static let engineNeutralScaleWeight = 10.0
    static let neutralScaleWeightSweep = [1.0, engineNeutralScaleWeight, 100.0]

    let model: Model
    let fittedOn: FitSet
    /// Neutral-scale row weight; lattice rows by 1. Residuals are unweighted.
    let neutralScaleWeight: Double
    /// Rows: printing density R, G, B. Columns: dye amounts C, M, Y or Status M R, G, B.
    let matrix: [[Double]]
    let offset: [Double]?
    let neutralScale: Residuals
    let lattice: Residuals

    var formula: String { model.formula }

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

    /// Every combination of `latticeSteps` amounts from 0 to each dye's maximum, cyan slowest.
    static func lattice(maxAmounts: [Double]) -> [[Double]] {
        let fractions = (0..<latticeSteps).map { Double($0) / Double(latticeSteps - 1) }
        return fractions.flatMap { c in fractions.flatMap { m in fractions.map { y in zip([c, m, y], maxAmounts).map { $0 * $1 } } } }
    }
}

extension PrintingDensityConversion.Point {
    init(
        dyeAmounts: [Double], statusM: NegativeDyeSet.Densitometer, printingDensity: NegativeDyeSet.Densitometer
    ) {
        self.init(
            dyeAmounts: dyeAmounts, statusM: statusM.densityAboveMinimum(dyeAmounts),
            printingDensity: printingDensity.densityAboveMinimum(dyeAmounts))
    }
}
