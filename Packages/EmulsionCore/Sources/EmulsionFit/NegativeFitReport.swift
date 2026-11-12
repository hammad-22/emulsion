import Foundation

/// Everything a negative fit found, for people and for MOV-25: both parameterisations, parameters ± standard error,
/// where the model misses, and every sample. Encodes with sorted keys so two runs write byte-identical files.
struct NegativeFitReport: Codable, Sendable, Equatable {
    /// MOV-106 acceptance: shared-range RMS residual below this, in density, on `targetStock` only.
    static let targetRMS = 0.03
    /// The one stock MOV-106 sets `targetRMS` for; other stocks are compared with it, not judged by it.
    static let targetStock = "kodak-vision3-250d-5207"

    let tool: String
    let stock: String
    let source: StockManifest.Source
    let characteristicSHA256: String
    let densitometry: String
    let midGrayLogExposure: Double
    let notes: [String]
    let digitizingUncertainty: StockManifest.Uncertainty
    let bounds: Bounds
    let targetRMS: Double
    let targetStock: String
    /// Whether the shared-range RMS is below `targetRMS`; nil unless this report is for `targetStock`.
    let sharedRangeMeetsTarget: Bool?
    let fits: [Fit]

    struct Bounds: Codable, Sendable, Equatable {
        let minimumDensity: [Double]
        let gamma: [Double]
        let densityRange: [Double]
        let exposureOffset: [Double]
    }

    struct Fit: Codable, Sendable, Equatable {
        let parameterization: NegativeFit.Parameterization
        let parameterCount: Int
        let optimizer: Optimizer
        let layers: [LayerFit]
        /// Caveats specific to this fit, e.g. a minimum density held on its bound.
        let notes: [String]
        let overall: Statistics
        let samples: [Sample]
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

    /// A fitted value and its fit-statistics standard error (nil on a bound or when JᵀJ is singular).
    struct Estimate: Codable, Sendable, Equatable {
        let value: Double
        let standardError: Double?
    }

    struct LayerFit: Codable, Sendable, Equatable {
        let layer: NegativeFit.Layer
        let minimumDensity: Estimate
        /// When true the fitted minimum density is not a reading of the film's base density: the logistic's long toe
        /// absorbs it.
        let minimumDensityOnBound: Bool
        /// The lowest traced density of this layer, for comparison with `minimumDensity`.
        let measuredLowestDensity: Double
        let gamma: Estimate
        /// Least-squares slope of the traced curve over the middle third of its density span: the datasheet-style
        /// straight-line gamma, for comparison with the logistic's centre slope `gamma`.
        let straightLineGamma: Double?
        let densityRange: Estimate
        let exposureOffset: Estimate
        let statistics: Statistics
        /// Mean residual over the low, middle and high third of the layer's exposure span, to show systematic misfit.
        let exposureThirds: [Third]
        /// Fitted samples inside the manifest's interpolated or shared spans: read from a bridged or merged line, not
        /// this curve's own trace. They are fitted with full weight like the rest.
        let interpolatedSampleCount: Int
    }

    struct Statistics: Codable, Sendable, Equatable {
        let sampleCount: Int
        let rms: Double
        let maxAbsResidual: Double
        let maxAbsLogExposure: Double
        let maxAbsLayer: NegativeFit.Layer
    }

    struct Third: Codable, Sendable, Equatable {
        let name: String
        let fromLogExposure: Double
        let toLogExposure: Double
        let sampleCount: Int
        let meanResidual: Double
    }

    /// Residual = measured − fitted density.
    struct Sample: Codable, Sendable, Equatable {
        let layer: NegativeFit.Layer
        let logExposure: Double
        let measured: Double
        let fitted: Double
        let residual: Double
    }

    func fit(_ parameterization: NegativeFit.Parameterization) -> Fit? { fits.first { $0.parameterization == parameterization } }

    func encoded() throws(NegativeFitError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw .encodingFailed(error.localizedDescription)
        }
    }

    /// `log_exposure_lux_s,layer,measured,fitted_shared_range,fitted_per_layer_range`, one row per sample, for plotting.
    func plotTable() -> String {
        let shared = fit(.sharedRange)?.samples ?? []
        let perLayer = fit(.perLayerRange)?.samples ?? []
        let rows = zip(shared, perLayer).map { a, b in
            [
                String(a.logExposure), a.layer.rawValue, String(a.measured), String(format: "%.6f", a.fitted),
                String(format: "%.6f", b.fitted),
            ]
            .joined(separator: ",")
        }
        return (["log_exposure_lux_s,layer,measured,fitted_shared_range,fitted_per_layer_range"] + rows).joined(separator: "\n") + "\n"
    }

    /// Fits both parameterisations to the stock's characteristic chart.
    /// - Parameter midGrayLogExposure: defaults to the chart's camera stop 0.
    static func fitting(_ stock: DigitizedStock, midGrayLogExposure: Double? = nil, tool: String) throws(NegativeFitError) -> Self {
        let chart = stock.characteristic
        guard stock.manifest.filmType == .cameraNegative else { throw .notACameraNegative(stock.id) }
        guard let midGray = midGrayLogExposure ?? chart.entry.cameraStops?.stopZeroLogExposure else {
            throw .missingCameraStops(stock.id)
        }
        let curves = NegativeFit.Layer.allCases.compactMap { chart.curve(named: $0.rawValue) }
        guard curves.count == NegativeFit.Layer.allCases.count else { throw .missingLayers(stock.id) }
        let untracedSpans = NegativeFit.Layer.allCases.map { chart.entry.curves[$0.rawValue]?.untracedSpans ?? [] }
        let fits = NegativeFit.Parameterization.allCases.map {
            fit(NegativeFit(curves: curves, midGrayLogExposure: midGray, parameterization: $0), untracedSpans: untracedSpans)
        }
        let sharedRMS = fits.first { $0.parameterization == .sharedRange }?.overall.rms
        return NegativeFitReport(
            tool: tool, stock: stock.id, source: stock.manifest.source, characteristicSHA256: chart.sha256,
            densitometry: chart.entry.conditions, midGrayLogExposure: midGray,
            notes: [
                "Residual = measured − fitted density, in the chart's densitometry.",
                "midGrayLogExposure approximates where an 18% gray card at normal exposure sits on the chart's log10 exposure axis"
                    + (midGrayLogExposure == nil ? " (default: camera stop 0 on the chart)" : " (set on the command line)")
                    + ". The chart's stop axis and log axis disagree slightly; it shifts the offsets only, not the fit quality.",
                "Standard errors are fit statistics (σ²·(JᵀJ)⁻¹ over the parameters not on a bound, σ² = SSR / (n − p_free)) "
                    + "and exclude the digitizing error.",
                "minimumDensity (base + fog + mask) is fitted but not used by the engine: the printer lights absorb it.",
                "straightLineGamma is the least-squares slope over the middle third of each traced layer's density span; gamma "
                    + "is the logistic's slope at its centre.",
            ],
            digitizingUncertainty: chart.entry.uncertainty,
            bounds: Bounds(
                minimumDensity: endpoints(NegativeFit.minimumDensityBounds), gamma: endpoints(NegativeFit.gammaBounds),
                densityRange: endpoints(NegativeFit.densityRangeBounds), exposureOffset: endpoints(NegativeFit.exposureOffsetBounds)),
            targetRMS: targetRMS, targetStock: targetStock,
            sharedRangeMeetsTarget: stock.id == targetStock ? sharedRMS.map { $0 < targetRMS } : nil, fits: fits)
    }

    /// - Parameter untracedSpans: per layer, the manifest's interpolated and shared x spans.
    private static func fit(_ model: NegativeFit, untracedSpans: [[[Double]]]) -> Fit {
        let result = model.solve()
        let names = model.parameterNames
        let estimates = Dictionary(
            uniqueKeysWithValues: names.indices.map {
                (names[$0], Estimate(value: result.parameters[$0], standardError: result.standardErrors[$0]))
            })
        let fitted = model.layerCurves(result.parameters)
        let samples = NegativeFit.Layer.allCases.indices.flatMap { c in
            zip(model.curves[c].x, model.curves[c].y).map { x, measured in
                let density = model.density(fitted[c], logExposure: x)
                return Sample(
                    layer: NegativeFit.Layer.allCases[c], logExposure: x, measured: measured, fitted: density, residual: measured - density)
            }
        }
        let layers = zip(NegativeFit.Layer.allCases, zip(model.curves, untracedSpans)).map { layer, curveAndSpans in
            let (curve, spans) = curveAndSpans
            func estimate(_ name: String) -> Estimate {
                estimates["\(layer.rawValue).\(name)"] ?? estimates[name] ?? Estimate(value: .nan, standardError: nil)
            }
            let own = samples.filter { $0.layer == layer }
            return LayerFit(
                layer: layer, minimumDensity: estimate("minimumDensity"),
                minimumDensityOnBound: names.indices.contains { names[$0] == "\(layer.rawValue).minimumDensity" && result.atBound[$0] },
                measuredLowestDensity: curve.y.min() ?? .nan, gamma: estimate("gamma"),
                straightLineGamma: NegativeFit.straightLineGamma(curve), densityRange: estimate("densityRange"),
                exposureOffset: estimate("exposureOffset"), statistics: statistics(own), exposureThirds: thirds(own),
                interpolatedSampleCount: curve.x.count(where: { x in spans.contains { $0[0] <= x && x <= $0[1] } }))
        }
        let notes = layers.filter(\.minimumDensityOnBound).map(minimumDensityOnBoundNote)
        return Fit(
            parameterization: model.parameterization, parameterCount: names.count,
            optimizer: Optimizer(
                path: result.path, termination: result.termination, converged: result.termination.converged, iterations: result.iterations,
                nelderMeadEvaluations: result.nelderMeadEvaluations,
                parametersOnBounds: names.indices.filter { result.atBound[$0] }.map { names[$0] },
                standardErrorNote: result.standardErrorNote),
            layers: layers, notes: notes, overall: statistics(samples), samples: samples)
    }

    private static func minimumDensityOnBoundNote(_ layer: LayerFit) -> String {
        "\(layer.layer.rawValue): fitted minimum density \(String(format: "%.3f", layer.minimumDensity.value)) sits on its bound, so it is "
            + "not a reading of the film's base density (the logistic's long toe absorbs it); the lowest traced density is "
            + String(format: "%.3f.", layer.measuredLowestDensity)
    }

    static func statistics(_ samples: [Sample]) -> Statistics {
        let worst = samples.indices.max { abs(samples[$0].residual) < abs(samples[$1].residual) }
        return Statistics(
            sampleCount: samples.count, rms: samples.map(\.residual).rms,
            maxAbsResidual: worst.map { abs(samples[$0].residual) } ?? 0, maxAbsLogExposure: worst.map { samples[$0].logExposure } ?? .nan,
            maxAbsLayer: worst.map { samples[$0].layer } ?? .red)
    }

    private static func thirds(_ samples: [Sample]) -> [Third] {
        guard let low = samples.map(\.logExposure).min(), let high = samples.map(\.logExposure).max() else { return [] }
        let width = (high - low) / 3
        return ["toe", "middle", "shoulder"].enumerated().map { index, name in
            let from = low + Double(index) * width
            let to = index == 2 ? high : from + width
            let inside = samples.filter { $0.logExposure >= from && (index == 2 ? $0.logExposure <= to : $0.logExposure < to) }
            let mean = inside.isEmpty ? 0 : inside.reduce(0) { $0 + $1.residual } / Double(inside.count)
            return Third(name: name, fromLogExposure: from, toLogExposure: to, sampleCount: inside.count, meanResidual: mean)
        }
    }

    private static func endpoints(_ range: ClosedRange<Double>) -> [Double] { [range.lowerBound, range.upperBound] }
}
