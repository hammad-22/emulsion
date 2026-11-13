import EmulsionCore

/// Fits the engine's negative characteristic curve to a datasheet's red, green and blue curves. Per layer c, with x
/// the chart's log10 exposure (lux-seconds):
///
///     D_c(x) = minimumDensity_c + FilmModel.negativeDensity(x − midGrayLogExposure, gamma_c, densityRange, exposureOffset_c)
///
/// `minimumDensity_c` (base + fog + mask, in the chart's densitometry) is fitted but not used by the engine: a
/// constant per-layer density is absorbed by the calibrated printer lights.
struct NegativeFit {
    enum Layer: String, CaseIterable, Codable, Sendable { case red, green, blue }

    enum Parameterization: String, CaseIterable, Codable, Sendable {
        /// One density range for all layers, as `FilmStock.Negative` holds it (10 parameters).
        case sharedRange
        /// A range per layer (12 parameters); diagnostic, to judge whether the engine curve needs one (MOV-25).
        case perLayerRange
    }

    struct LayerCurve: Sendable, Equatable {
        var minimumDensity: Double
        var gamma: Double
        var densityRange: Double
        var exposureOffset: Double
    }

    /// Densities are non-negative; 2 D is far above the base + fog + mask of a camera negative.
    static let minimumDensityBounds = 0.0...2.0
    /// Brackets camera-negative slopes (around 0.5–0.7 D per log10 exposure) with a wide margin.
    static let gammaBounds = 0.2...1.5
    /// From less than the visible span up to a range so wide the logistic is nearly straight across a chart.
    static let densityRangeBounds = 0.5...8.0
    /// Curve centers up to 4 log10 under and 6 over mid-gray: the charts span under 5 log10 in all.
    static let exposureOffsetBounds = -4.0...6.0

    /// Red, green and blue, in that order.
    let curves: [DigitizedCurve]
    let midGrayLogExposure: Double
    let parameterization: Parameterization

    var parameterNames: [String] {
        let layers = Layer.allCases.map(\.rawValue)
        let ranges = parameterization == .sharedRange ? ["densityRange"] : layers.map { "\($0).densityRange" }
        return layers.map { "\($0).minimumDensity" } + layers.map { "\($0).gamma" } + ranges + layers.map { "\($0).exposureOffset" }
    }

    var bounds: [ClosedRange<Double>] {
        let rangeCount = parameterization == .sharedRange ? 1 : 3
        return Array(repeating: Self.minimumDensityBounds, count: 3) + Array(repeating: Self.gammaBounds, count: 3)
            + Array(repeating: Self.densityRangeBounds, count: rangeCount) + Array(repeating: Self.exposureOffsetBounds, count: 3)
    }

    func layerCurves(_ p: [Double]) -> [LayerCurve] {
        let shared = parameterization == .sharedRange
        let offsetStart = shared ? 7 : 9
        return (0..<3).map {
            LayerCurve(minimumDensity: p[$0], gamma: p[3 + $0], densityRange: p[shared ? 6 : 6 + $0], exposureOffset: p[offsetStart + $0])
        }
    }

    func parameters(_ layers: [LayerCurve]) -> [Double] {
        let ranges = parameterization == .sharedRange ? [layers.map(\.densityRange).max() ?? 0] : layers.map(\.densityRange)
        return layers.map(\.minimumDensity) + layers.map(\.gamma) + ranges + layers.map(\.exposureOffset)
    }

    func density(_ curve: LayerCurve, logExposure: Double) -> Double {
        curve.minimumDensity
            + FilmModel.negativeDensity(
                logExposure: logExposure - midGrayLogExposure, gamma: curve.gamma, densityRange: curve.densityRange,
                exposureOffset: curve.exposureOffset)
    }

    /// Measured minus fitted density: red samples, then green, then blue.
    func residuals(_ p: [Double]) -> [Double] {
        zip(curves, layerCurves(p)).flatMap { curve, layer in zip(curve.x, curve.y).map { $1 - density(layer, logExposure: $0) } }
    }

    /// Read off the data: the lowest density, the straight-line gamma, and the exposure where the curve crosses halfway
    /// up its density span.
    func startingPoint() -> [Double] {
        let layers = curves.map { curve -> LayerCurve in
            let low = curve.y.min() ?? 0
            let span = (curve.y.max() ?? 0) - low
            let half = low + span / 2
            let crossing = curve.x.indices.first { curve.y[$0] >= half }.map { curve.x[$0] } ?? curve.x[curve.x.count / 2]
            return LayerCurve(
                minimumDensity: low, gamma: Self.straightLineGamma(curve) ?? 1, densityRange: span,
                exposureOffset: crossing - midGrayLogExposure)
        }
        return parameters(layers).clamped(lower: bounds.map(\.lowerBound), upper: bounds.map(\.upperBound))
    }

    /// The datasheet-style "straight-line" gamma: least-squares slope of density against log10 exposure over the samples
    /// in the middle third of the curve's density span. nil with fewer than two such samples.
    static func straightLineGamma(_ curve: DigitizedCurve) -> Double? {
        guard let low = curve.y.min(), let high = curve.y.max() else { return nil }
        let span = high - low
        let middle = curve.y.indices.filter { curve.y[$0] >= low + span / 3 && curve.y[$0] <= low + 2 * span / 3 }
        guard middle.count >= 2 else { return nil }
        let meanX = middle.reduce(0) { $0 + curve.x[$1] } / Double(middle.count)
        let meanY = middle.reduce(0) { $0 + curve.y[$1] } / Double(middle.count)
        let covariance = middle.reduce(0) { $0 + (curve.x[$1] - meanX) * (curve.y[$1] - meanY) }
        let variance = middle.reduce(0) { $0 + (curve.x[$1] - meanX) * (curve.x[$1] - meanX) }
        return variance > 0 ? covariance / variance : nil
    }

    func solve() -> LeastSquares.Result {
        LeastSquares(lower: bounds.map(\.lowerBound), upper: bounds.map(\.upperBound), residuals: residuals).minimize(from: startingPoint())
    }
}
