import Foundation

/// What `emulsion-fit dyes` computes for a camera negative from its digitized dye spectra and characteristic curves,
/// through the Status M, APD and RP 180 responsivities: the midscale reconstruction (MOV-88 acceptance), the mask
/// check, the neutral scale in dye amounts and printing densities, straight-line gammas, and the printing-density
/// conversions. Every number is computed from digitized datasheet data, not measured on film. Encodes with sorted keys
/// so two runs write byte-identical files.
struct NegativeDyeSetReport: Codable, Sendable, Equatable {
    /// The midscale check uses 10 nm steps within 400–700 nm, where the image dyes dominate.
    static let midscaleWavelengths = 400.0...700.0
    static let midscaleWavelengthStep = 10.0
    /// ADX scales Dmin-subtracted APD by k = (1.00, 0.92, 0.95) for red, green, blue (ST 2065-3:2020 Eqs. 1–2).
    static let adxChannelFactors = [1.00, 0.92, 0.95]

    let tool: String
    let stock: String
    let source: StockManifest.Source
    let spectralDyeDensitySHA256: String
    let characteristicSHA256: String
    let standards: [StandardsManifest.Entry]
    let wavelengthGrid: [Double]
    let notes: [String]
    let midscale: Midscale
    let mask: [MaskRow]
    let gammas: [GammaRow]
    let latticeMaxAmounts: [Double]
    let latticeSteps: Int
    /// Through APD (SMPTE ST 2065-2); holds the engine's matrix.
    let academyConversions: ConversionSet
    /// Through RP 180 printing density.
    let rp180Conversions: ConversionSet
    let dyeEdgeDiagnostic: EdgeDiagnostic
    let neutralScale: [NeutralScale.Sample]

    struct Midscale: Codable, Sendable, Equatable {
        let wavelengths: [Double]
        /// Cyan, magenta, yellow.
        let amounts: [Double]
        let rms: Double
        let maxAbsResidual: Double
        let wavelengthOfMax: Double
        let targetMaxResidual: Double
        let meetsTarget: Bool
    }

    /// Integral density of the minimum-density spectrum against the characteristic chart's lowest traced density
    /// (the chart is Status M, so only the Status M row compares like with like).
    struct MaskRow: Codable, Sendable, Equatable {
        let densityDefinition: String
        let minimumDensity: [Double]
        let chartLowest: [Double]
        /// minimumDensity − chartLowest.
        let difference: [Double]
    }

    /// Straight-line gammas (middle third of each curve's span), red/cyan, green/magenta, blue/yellow.
    struct GammaRow: Codable, Sendable, Equatable {
        let quantity: String
        let values: [Double?]
    }

    /// The neutral scale's straight-line gammas (`NegativeFit.straightLineGamma`), red/cyan, green/magenta, blue/yellow.
    struct Gammas: Sendable, Equatable {
        enum Quantity: CaseIterable, Sendable {
            case statusM, dyeAmounts, academyPrintingDensity, rp180PrintingDensity, academyADX

            var label: String {
                switch self {
                case .statusM: "Status M"
                case .dyeAmounts: "Dye amounts (C, M, Y)"
                case .academyPrintingDensity: "APD"
                case .rp180PrintingDensity: "RP 180 PD"
                case .academyADX: "APD × ADX k (1.00, 0.92, 0.95)"
                }
            }
        }

        let statusM: [Double?]
        let dyeAmounts: [Double?]
        let academyPrintingDensity: [Double?]
        let rp180PrintingDensity: [Double?]

        init(_ scale: NeutralScale) {
            func gammas(_ quantity: Quantity, _ value: @escaping (NeutralScale.Sample) -> [Double]) -> [Double?] {
                (0..<3).map { NegativeFit.straightLineGamma(scale.curve(quantity.label, channel: $0, value)) }
            }
            statusM = gammas(.statusM, \.statusM)
            dyeAmounts = gammas(.dyeAmounts, \.dyeAmounts)
            academyPrintingDensity = gammas(.academyPrintingDensity, \.academyPrintingDensity)
            rp180PrintingDensity = gammas(.rp180PrintingDensity, \.rp180PrintingDensity)
        }

        func values(_ quantity: Quantity) -> [Double?] {
            switch quantity {
            case .statusM: statusM
            case .dyeAmounts: dyeAmounts
            case .academyPrintingDensity: academyPrintingDensity
            case .rp180PrintingDensity: rp180PrintingDensity
            case .academyADX: zip(academyPrintingDensity, adxChannelFactors).map { gamma, k in gamma.map { $0 * k } }
            }
        }

        func rows(_ quantities: [Quantity] = Quantity.allCases) -> [GammaRow] {
            quantities.map { GammaRow(quantity: $0.label, values: values($0)) }
        }
    }

    struct ConversionSet: Codable, Sendable, Equatable {
        let printingDensity: String
        let fits: [PrintingDensityConversion]

        /// Every fit the report compares: each model on the neutral scale and lattice, the engine form at each
        /// `neutralScaleWeightSweep` weight, and the Status M fits on the neutral scale alone.
        static func fitting(
            printingDensity: String, neutralScale: [PrintingDensityConversion.Point], lattice: [PrintingDensityConversion.Point]
        ) throws(DyeSetError) -> ConversionSet {
            var fits: [PrintingDensityConversion] = []
            for model in PrintingDensityConversion.Model.allCases {
                fits.append(try PrintingDensityConversion.fit(model, neutralScale: neutralScale, lattice: lattice))
            }
            for weight in PrintingDensityConversion.neutralScaleWeightSweep where weight != 1 {
                fits.append(
                    try PrintingDensityConversion.fit(
                        .dyeAmountsWithOffset, neutralScaleWeight: weight, neutralScale: neutralScale, lattice: lattice))
            }
            for model in [PrintingDensityConversion.Model.statusM, .statusMWithOffset] {
                fits.append(try PrintingDensityConversion.fit(model, on: .neutralScale, neutralScale: neutralScale, lattice: lattice))
            }
            return ConversionSet(printingDensity: printingDensity, fits: fits)
        }

        func fit(
            _ model: PrintingDensityConversion.Model, fittedOn fitSet: PrintingDensityConversion.FitSet = .neutralScaleAndLattice,
            neutralScaleWeight: Double = 1
        ) -> PrintingDensityConversion? {
            fits.first { $0.model == model && $0.fittedOn == fitSet && $0.neutralScaleWeight == neutralScaleWeight }
        }

        /// The conversion the engine uses.
        var engine: PrintingDensityConversion? {
            fit(.dyeAmountsWithOffset, neutralScaleWeight: PrintingDensityConversion.engineNeutralScaleWeight)
        }
    }

    /// How much zero-filling the dye curves outside their traced spans, instead of holding the end values, changes
    /// the neutral scale: the largest absolute change of any channel at any sample, and of any entry of the engine's APD
    /// matrix.
    struct EdgeDiagnostic: Codable, Sendable, Equatable {
        let dyeAmounts: Double
        let academyPrintingDensity: Double
        let rp180PrintingDensity: Double
        let academyDyeMatrix: Double
    }

    var conversions: [ConversionSet] { [academyConversions, rp180Conversions] }

    /// The engine's printing-density matrix, through APD.
    var academyEngineConversion: PrintingDensityConversion? { academyConversions.engine }

    /// What the report is built from and a negative fit reuses.
    struct Reconstruction: Sendable {
        let dyeSet: NegativeDyeSet
        let neutralScale: NeutralScale
        /// The characteristic chart's lowest traced Status M density, red, green, blue.
        let chartLowest: [Double]
        let gammas: Gammas
        /// `academyEngineConversion`.
        let engineConversion: PrintingDensityConversion
    }

    static func making(_ stock: DigitizedStock, standards: StandardsTables, tool: String) throws(DyeSetError) -> Self {
        try reconstructing(stock, standards: standards, tool: tool).report
    }

    /// The report and the reconstruction it is built from.
    static func reconstructing(_ stock: DigitizedStock, standards: StandardsTables, tool: String) throws(DyeSetError)
        -> (report: Self, reconstruction: Reconstruction)
    {
        guard stock.manifest.filmType == .cameraNegative else { throw .notACameraNegative(stock.id) }
        let chart = stock.spectralDyeDensity
        let dyeSet = try NegativeDyeSet(chart: chart, stock: stock.id)
        let midscale = try midscale(chart, stock: stock.id)

        let layers = SpectralResponsivities.Channel.allCases.map(\.rawValue)
        guard let characteristic = stock.characteristic.aligned(layers) else {
            throw .missingCurve(stock: stock.id, curve: "characteristic red, green and blue")
        }
        let chartLowest = characteristic.columns.map { $0.min() ?? 0 }
        let scale = try NeutralScale.solve(
            logExposure: characteristic.x, densities: characteristic.columns, dyeSet: dyeSet, standards: standards)

        let mask = [standards.statusM, standards.academyPrintingDensity, standards.rp180].map { responsivities in
            let density = dyeSet.densitometer(responsivities).minimumDensities
            return MaskRow(
                densityDefinition: responsivities.name, minimumDensity: density, chartLowest: chartLowest,
                difference: zip(density, chartLowest).map { $0 - $1 })
        }

        let maxAmounts = NegativeDyeSet.Dye.allCases.indices.map { k in scale.samples.map { $0.dyeAmounts[k] }.max() ?? 0 }
        let lattice = PrintingDensityConversion.lattice(maxAmounts: maxAmounts)
        let academy = try conversionSet(
            standards.academyPrintingDensity, dyeSet: dyeSet, statusM: standards.statusM, scale: scale,
            printingDensity: \.academyPrintingDensity, lattice: lattice)
        let rp180 = try conversionSet(
            standards.rp180, dyeSet: dyeSet, statusM: standards.statusM, scale: scale, printingDensity: \.rp180PrintingDensity,
            lattice: lattice)
        guard let engineConversion = academy.engine else {
            throw .singularFit(PrintingDensityConversion.Model.dyeAmountsWithOffset.formula)
        }

        let zeroFilled = try NegativeDyeSet(chart: chart, stock: stock.id, dyeEdge: .zero)
        let zeroScale = try NeutralScale.solve(
            logExposure: characteristic.x, densities: characteristic.columns, dyeSet: zeroFilled, standards: standards)
        let zeroAcademy = try conversionSet(
            standards.academyPrintingDensity, dyeSet: zeroFilled, statusM: standards.statusM, scale: zeroScale,
            printingDensity: \.academyPrintingDensity, lattice: lattice)
        func largestChange(_ value: (NeutralScale.Sample) -> [Double]) -> Double {
            zip(scale.samples, zeroScale.samples).flatMap { zip(value($0), value($1)).map { $0 - $1 } }.maxAbs
        }
        func matrix(_ set: ConversionSet) -> [Double] { set.engine?.matrix.flatMap { $0 } ?? [] }
        let edge = EdgeDiagnostic(
            dyeAmounts: largestChange(\.dyeAmounts), academyPrintingDensity: largestChange(\.academyPrintingDensity),
            rp180PrintingDensity: largestChange(\.rp180PrintingDensity),
            academyDyeMatrix: zip(matrix(academy), matrix(zeroAcademy)).map { $0 - $1 }.maxAbs)

        let gammas = Gammas(scale)
        let report = NegativeDyeSetReport(
            tool: tool, stock: stock.id, source: stock.manifest.source, spectralDyeDensitySHA256: chart.sha256,
            characteristicSHA256: stock.characteristic.sha256, standards: standards.provenance, wavelengthGrid: dyeSet.wavelengths,
            notes: notes, midscale: midscale, mask: mask, gammas: gammas.rows(), latticeMaxAmounts: maxAmounts,
            latticeSteps: PrintingDensityConversion.latticeSteps, academyConversions: academy, rp180Conversions: rp180,
            dyeEdgeDiagnostic: edge, neutralScale: scale.samples)
        return (
            report,
            Reconstruction(
                dyeSet: dyeSet, neutralScale: scale, chartLowest: chartLowest, gammas: gammas, engineConversion: engineConversion)
        )
    }

    static let notes = [
        "Every number is computed from the digitized datasheet spectra and curves through the standards' responsivities; "
            + "none is a measurement of film.",
        "Dye curves are the sheet's \"D-mins subtracted\", peak-normalized spectra: net density per unit dye, including the "
            + "masking coupler consumed. Minimum density is base + fog + unused masking couplers.",
        "Spectral density D(λ) = Dmin(λ) + Σ c_k ε_k(λ); integral density D_c = −log10(Σ Π_c 10^−D / Σ Π_c) on a 5 nm grid, "
            + "360–800 nm. Outside a curve's traced span its end value is held (assumption; dyeEdgeDiagnostic gives the effect "
            + "of zero-filling the dyes instead).",
        "Neutral scale: at each characteristic sample, the dye amounts whose Status M density above Dmin equals the chart "
            + "density above its lowest traced density (Newton, |error| ≤ 1e-10 D).",
        "Conversions are fitted by linear least squares on the neutral-scale samples plus a 9×9×9 lattice of dye amounts "
            + "from 0 to each dye's neutral-scale maximum (fittedOn neutralScaleAndLattice); the Status M fits are repeated on "
            + "the neutral scale alone (fittedOn neutralScale). Residual = printing density − fitted, per channel, reported "
            + "unweighted on both sample sets.",
        "The engine's matrix is PD ≈ P·c + b with each neutral-scale row weighted by its neutralScaleWeight, "
            + "\(Int(PrintingDensityConversion.engineNeutralScaleWeight)) (lattice rows by 1): the neutral scale sets tone and gray balance, and the calibrated printer lights absorb the offset b. "
            + "The same fit at the other neutralScaleWeight values is reported for comparison.",
        "Gammas are least-squares slopes over the middle third of each curve's span, per log10 lux-second.",
    ]

    private static func midscale(_ chart: DigitizedChart, stock: String) throws(DyeSetError) -> Midscale {
        let comparison = DyeSumCheck.Comparison(
            subtractsMinimumDensity: true, wavelengths: midscaleWavelengths, wavelengthStep: midscaleWavelengthStep)
        guard let check = DyeSumCheck.compared(chart, comparison) else { throw .noMidscaleOverlap(stock) }
        let byDye = Dictionary(uniqueKeysWithValues: zip(DyeSumCheck.dyes, check.scales))
        return Midscale(
            wavelengths: check.wavelengths, amounts: NegativeDyeSet.Dye.allCases.map { byDye[$0.rawValue] ?? 0 }, rms: check.rms,
            maxAbsResidual: check.maxAbsResidual, wavelengthOfMax: check.wavelengthOfMax,
            targetMaxResidual: DyeSumCheck.targetMaxResidual, meetsTarget: check.meetsTarget)
    }

    private static func conversionSet(
        _ responsivities: SpectralResponsivities, dyeSet: NegativeDyeSet, statusM: SpectralResponsivities, scale: NeutralScale,
        printingDensity: KeyPath<NeutralScale.Sample, [Double]>, lattice: [[Double]]
    ) throws(DyeSetError) -> ConversionSet {
        let neutral = scale.samples.map {
            PrintingDensityConversion.Point(dyeAmounts: $0.dyeAmounts, statusM: $0.statusM, printingDensity: $0[keyPath: printingDensity])
        }
        let (statusM, printing) = (dyeSet.densitometer(statusM), dyeSet.densitometer(responsivities))
        let box = lattice.map { PrintingDensityConversion.Point(dyeAmounts: $0, statusM: statusM, printingDensity: printing) }
        return try ConversionSet.fitting(printingDensity: responsivities.name, neutralScale: neutral, lattice: box)
    }

    /// `log_exposure_lux_s`, Status M, dye amounts, APD and RP 180 printing density above minimum, one row per sample.
    func neutralScaleTable() -> String {
        let header =
            "log_exposure_lux_s,status_m_red,status_m_green,status_m_blue,cyan,magenta,yellow,"
            + "apd_red,apd_green,apd_blue,rp180_red,rp180_green,rp180_blue"
        let rows = neutralScale.map { sample in
            ([String(sample.logExposure)]
                + (sample.statusM + sample.dyeAmounts + sample.academyPrintingDensity + sample.rp180PrintingDensity).map {
                    String(format: "%.6f", $0)
                })
                .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}
