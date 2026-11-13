import Foundation

/// Everything a negative fit found, for people and for MOV-25: both curve forms per layer, parameters ± standard
/// error, residuals in dye amount and in the chart's own Status M, the straight-line gammas, how far the shoulder is
/// extrapolated, the printing-density matrix written to the stock, and every sample. Encodes with sorted keys so two
/// runs write byte-identical files.
struct NegativeFitReport: Codable, Sendable, Equatable {
    /// MOV-25 acceptance: toe-and-shoulder Status M RMS residual at most this, in density, per layer, on `targetStock`.
    static let targetRMS = 0.03
    /// The one stock MOV-25 sets `targetRMS` for; other stocks are compared with it, not judged by it.
    static let targetStock = "kodak-vision3-250d-5207"
    /// The straight-line gammas reported.
    static let gammaQuantities: [NegativeDyeSetReport.Gammas.Quantity] = [.statusM, .dyeAmounts, .academyPrintingDensity]

    let tool: String
    let stock: String
    let source: StockManifest.Source
    let characteristicSHA256: String
    let spectralDyeDensitySHA256: String
    let standards: [StandardsManifest.Entry]
    let densitometry: String
    let midGrayLogExposure: Double
    let notes: [String]
    let digitizingUncertainty: StockManifest.Uncertainty
    /// Per curve form, per parameter: [lower, upper].
    let bounds: [String: [String: [Double]]]
    let targetRMS: Double
    let targetStock: String
    /// Whether every layer's toe-and-shoulder Status M RMS is at most `targetRMS`; nil unless this is `targetStock`.
    let meetsTarget: Bool?
    let gammas: [NegativeDyeSetReport.GammaRow]
    /// The last sample every layer is traced at, in stops above mid-gray.
    let lastTracedStops: Double
    /// The engine's printing-density matrix (APD), written to the stock without its offset.
    let printingDensity: PrintingDensityConversion
    let fits: [Fit]

    struct Fit: Codable, Sendable, Equatable {
        let form: NegativeCurveForm
        let layers: [LayerFit]
        let samples: [Sample]
    }

    /// A fitted value and its fit-statistics standard error (nil on a bound or when JᵀJ is singular).
    struct Parameter: Codable, Sendable, Equatable {
        let name: String
        let value: Double
        let standardError: Double?
    }

    struct Optimizer: Codable, Sendable, Equatable {
        let path: LeastSquares.Path
        let termination: LeastSquares.Termination
        let converged: Bool
        let iterations: Int
        let nelderMeadEvaluations: Int
        let parametersOnBounds: [String]
        let standardErrorNote: String?
    }

    struct LayerFit: Codable, Sendable, Equatable {
        let layer: NegativeFit.Layer
        let parameters: [Parameter]
        let optimizer: Optimizer
        /// Measured − fitted dye amount.
        let dyeAmount: Statistics
        /// Traced Status M density − [lowest traced density + Status M of the dye stack at the three layers' fitted
        /// amounts]: the chart's own densitometry.
        let statusM: Statistics
        /// Fitted samples inside the manifest's interpolated or shared spans: read from a bridged or merged line, not
        /// this curve's own trace. They are fitted with full weight like the rest.
        let interpolatedSampleCount: Int
        /// Toe-and-shoulder only: the fitted shoulder exposure minus the last traced sample's, in stops (negative: inside
        /// the traced range).
        let shoulderBeyondLastTracedStops: Double?

        func value(_ name: String) -> Double? { parameters.first { $0.name == name }?.value }
    }

    struct Statistics: Codable, Sendable, Equatable {
        let sampleCount: Int
        let rms: Double
        let maxAbsResidual: Double
        let maxAbsLogExposure: Double
        /// Mean residual over the low, middle and high third of the exposure span, to show systematic misfit.
        let thirds: [Third]
    }

    struct Third: Codable, Sendable, Equatable {
        let name: String
        let fromLogExposure: Double
        let toLogExposure: Double
        let sampleCount: Int
        let meanResidual: Double
    }

    /// One layer at one exposure: traced and fitted dye amount and Status M density.
    struct Sample: Codable, Sendable, Equatable {
        let layer: NegativeFit.Layer
        let logExposure: Double
        let dyeAmount: Double
        let fittedDyeAmount: Double
        let statusM: Double
        let fittedStatusM: Double
    }

    func fit(_ form: NegativeCurveForm) -> Fit? { fits.first { $0.form == form } }

    /// One row per sample: traced dye amount and Status M with both forms' fits, for plotting.
    func plotTable() -> String {
        let header =
            "log_exposure_lux_s,layer,dye_amount,dye_amount_toe_shoulder,dye_amount_logistic,"
            + "status_m,status_m_toe_shoulder,status_m_logistic"
        let toeShoulder = fit(.toeShoulder)?.samples ?? []
        let logistic = fit(.logistic)?.samples ?? []
        let rows = zip(toeShoulder, logistic).map { a, b in
            ([String(a.logExposure), a.layer.rawValue]
                + [a.dyeAmount, a.fittedDyeAmount, b.fittedDyeAmount, a.statusM, a.fittedStatusM, b.fittedStatusM].map {
                    String(format: "%.6f", $0)
                })
                .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Reconstructs the stock's dye set, reads its neutral scale in dye amounts and fits both curve forms per layer.
    /// - Parameter midGrayLogExposure: defaults to the chart's camera stop 0.
    static func fitting(
        _ stock: DigitizedStock, standards: StandardsTables, midGrayLogExposure: Double? = nil, tool: String
    ) throws(NegativeFitError) -> Self {
        let chart = stock.characteristic
        guard stock.manifest.filmType == .cameraNegative else { throw .notACameraNegative(stock.id) }
        guard let midGray = midGrayLogExposure ?? chart.entry.cameraStops?.stopZeroLogExposure else {
            throw .missingCameraStops(stock.id)
        }
        guard chart.aligned(NegativeFit.Layer.allCases.map(\.rawValue)) != nil else { throw .missingLayers(stock.id) }
        let reconstruction: NegativeDyeSetReport.Reconstruction
        do {
            reconstruction = try NegativeDyeSetReport.reconstructing(stock, standards: standards, tool: tool).reconstruction
        } catch {
            throw .dyeSet(error)
        }
        let scale = reconstruction.neutralScale.samples
        let untracedSpans = NegativeFit.Layer.allCases.map { chart.entry.curves[$0.rawValue]?.untracedSpans ?? [] }
        let lastTraced = (scale.last?.logExposure ?? midGray) - midGray
        let fits = NegativeCurveForm.allCases.map { form in
            fit(
                form, scale: scale, midGray: midGray, lowest: reconstruction.chartLowest,
                statusM: reconstruction.dyeSet.densitometer(standards.statusM), lastTraced: lastTraced, untracedSpans: untracedSpans)
        }
        let toeShoulderRMS = fits.first { $0.form == .toeShoulder }?.layers.map(\.statusM.rms) ?? []
        return NegativeFitReport(
            tool: tool, stock: stock.id, source: stock.manifest.source, characteristicSHA256: chart.sha256,
            spectralDyeDensitySHA256: stock.spectralDyeDensity.sha256, standards: standards.provenance,
            densitometry: chart.entry.conditions, midGrayLogExposure: midGray,
            notes: notes(midGrayFromCommandLine: midGrayLogExposure != nil), digitizingUncertainty: chart.entry.uncertainty,
            bounds: Dictionary(
                uniqueKeysWithValues: NegativeCurveForm.allCases.map { form in
                    (
                        form.rawValue,
                        Dictionary(uniqueKeysWithValues: zip(form.parameterNames, form.bounds.map { [$0.lowerBound, $0.upperBound] }))
                    )
                }),
            targetRMS: targetRMS, targetStock: targetStock,
            meetsTarget: stock.id == targetStock ? toeShoulderRMS.allSatisfy { $0 <= targetRMS } : nil,
            gammas: reconstruction.gammas.rows(gammaQuantities), lastTracedStops: lastTraced / log10(2),
            printingDensity: reconstruction.engineConversion, fits: fits)
    }

    private static func notes(midGrayFromCommandLine: Bool) -> [String] {
        [
            "Dye amounts along the neutral scale come from the digitized dye set and Status M (see `emulsion-fit dyes`); every "
                + "number here is computed from the digitized datasheet, not measured on film.",
            "Per layer, dye amount = offset + curve(x), x = log10 exposure − midGrayLogExposure. The offset is fitted but not "
                + "stored: the printer lights absorb a constant per-layer density.",
            "toeShoulder is the engine's curve (FilmModel.negativeDyeAmount), written to the stock; logistic is the engine's "
                + "previous curve, for comparison only.",
            "Status M residual = traced density − [lowest traced density + Status M of the dye stack at the three layers' fitted "
                + "amounts, offsets included]. MOV-25 acceptance: RMS ≤ targetRMS per layer, on targetStock.",
            "midGrayLogExposure approximates where an 18% gray card at normal exposure sits on the chart's log10 exposure axis"
                + (midGrayFromCommandLine ? " (set on the command line)" : " (default: camera stop 0 on the chart)")
                + ". It shifts the exposures only, not the fit quality.",
            "shoulderExposure and shoulderWidth are fitted from the bend at the top of the traced data "
                + "(shoulderBeyondLastTracedStops: negative = inside the traced range). The curve beyond the last traced "
                + "sample, its flat top, is extrapolated.",
            "Standard errors are fit statistics (σ²·(JᵀJ)⁻¹ over the parameters not on a bound, σ² = SSR / (n − p_free)) "
                + "and exclude the digitizing error.",
            "Gammas are least-squares slopes over the middle third of each curve's span, per log10 lux-second.",
        ]
    }

    private static func fit(
        _ form: NegativeCurveForm, scale: [NeutralScale.Sample], midGray: Double, lowest: [Double],
        statusM: NegativeDyeSet.Densitometer, lastTraced: Double, untracedSpans: [[[Double]]]
    ) -> Fit {
        let x = scale.map { $0.logExposure - midGray }
        let results = NegativeFit.Layer.allCases.indices.map { layer in
            NegativeFit(curve: DigitizedCurve(name: form.rawValue, x: x, y: scale.map { $0.dyeAmounts[layer] }), form: form).solve()
        }
        let fittedAmounts = x.map { x in results.map { form.dyeAmount($0.parameters, at: x) } }
        let fittedStatusM = fittedAmounts.map { amounts in zip(statusM.densityAboveMinimum(amounts), lowest).map { $0 + $1 } }
        let samples = NegativeFit.Layer.allCases.enumerated().flatMap { layer, name in
            scale.indices.map { i in
                Sample(
                    layer: name, logExposure: scale[i].logExposure, dyeAmount: scale[i].dyeAmounts[layer],
                    fittedDyeAmount: fittedAmounts[i][layer], statusM: scale[i].statusM[layer] + lowest[layer],
                    fittedStatusM: fittedStatusM[i][layer])
            }
        }
        let layers = NegativeFit.Layer.allCases.enumerated().map { layer, name in
            let result = results[layer]
            let own = samples.filter { $0.layer == name }
            let names = form.parameterNames
            let shoulder = form == .toeShoulder ? names.firstIndex(of: "shoulderExposure").map { result.parameters[$0] } : nil
            return LayerFit(
                layer: name,
                parameters: names.indices.map {
                    Parameter(name: names[$0], value: result.parameters[$0], standardError: result.standardErrors[$0])
                },
                optimizer: Optimizer(
                    path: result.path, termination: result.termination, converged: result.termination.converged,
                    iterations: result.iterations, nelderMeadEvaluations: result.nelderMeadEvaluations,
                    parametersOnBounds: names.indices.filter { result.atBound[$0] }.map { names[$0] },
                    standardErrorNote: result.standardErrorNote),
                dyeAmount: statistics(own.map { ($0.logExposure, $0.dyeAmount - $0.fittedDyeAmount) }),
                statusM: statistics(own.map { ($0.logExposure, $0.statusM - $0.fittedStatusM) }),
                interpolatedSampleCount: own.count { sample in
                    untracedSpans[layer].contains { $0[0] <= sample.logExposure && sample.logExposure <= $0[1] }
                },
                shoulderBeyondLastTracedStops: shoulder.map { ($0 - lastTraced) / log10(2) })
        }
        return Fit(form: form, layers: layers, samples: samples)
    }

    /// - Parameter residuals: (log10 exposure, residual) pairs.
    static func statistics(_ residuals: [(x: Double, r: Double)]) -> Statistics {
        let worst = residuals.indices.max { abs(residuals[$0].r) < abs(residuals[$1].r) }
        return Statistics(
            sampleCount: residuals.count, rms: residuals.map(\.r).rms, maxAbsResidual: worst.map { abs(residuals[$0].r) } ?? 0,
            maxAbsLogExposure: worst.map { residuals[$0].x } ?? .nan, thirds: thirds(residuals))
    }

    private static func thirds(_ residuals: [(x: Double, r: Double)]) -> [Third] {
        guard let low = residuals.map(\.x).min(), let high = residuals.map(\.x).max() else { return [] }
        let width = (high - low) / 3
        return ["toe", "middle", "shoulder"].enumerated().map { index, name in
            let from = low + Double(index) * width
            let to = index == 2 ? high : from + width
            let inside = residuals.filter { $0.x >= from && (index == 2 ? $0.x <= to : $0.x < to) }
            let mean = inside.isEmpty ? 0 : inside.reduce(0) { $0 + $1.r } / Double(inside.count)
            return Third(name: name, fromLogExposure: from, toLogExposure: to, sampleCount: inside.count, meanResidual: mean)
        }
    }
}
