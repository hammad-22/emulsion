/// Fits one layer's neutral-scale dye amounts with a `NegativeCurveForm`, by bounded least squares.
struct NegativeFit {
    enum Layer: String, CaseIterable, Codable, Sendable { case red, green, blue }

    /// x: log10 exposure relative to mid-gray; y: dye amount above minimum density.
    let curve: DigitizedCurve
    let form: NegativeCurveForm

    /// Measured minus fitted dye amount, one per sample.
    func residuals(_ p: [Double]) -> [Double] { zip(curve.x, curve.y).map { $1 - form.dyeAmount(p, at: $0) } }

    func solve() -> LeastSquares.Result {
        let bounds = form.bounds
        return LeastSquares(lower: bounds.map(\.lowerBound), upper: bounds.map(\.upperBound), residuals: residuals)
            .minimize(from: form.startingPoint(curve))
    }

    /// Least-squares line through the samples in the middle third of the curve's y span. nil with fewer than two such
    /// samples.
    static func straightLine(_ curve: DigitizedCurve) -> (slope: Double, intercept: Double)? {
        guard let low = curve.y.min(), let high = curve.y.max() else { return nil }
        let span = high - low
        let middle = curve.y.indices.filter { curve.y[$0] >= low + span / 3 && curve.y[$0] <= low + 2 * span / 3 }
        guard middle.count >= 2 else { return nil }
        let meanX = middle.reduce(0) { $0 + curve.x[$1] } / Double(middle.count)
        let meanY = middle.reduce(0) { $0 + curve.y[$1] } / Double(middle.count)
        let covariance = middle.reduce(0) { $0 + (curve.x[$1] - meanX) * (curve.y[$1] - meanY) }
        let variance = middle.reduce(0) { $0 + (curve.x[$1] - meanX) * (curve.x[$1] - meanX) }
        guard variance > 0 else { return nil }
        let slope = covariance / variance
        return (slope, meanY - slope * meanX)
    }

    /// The datasheet-style "straight-line" gamma: the slope of `straightLine`.
    static func straightLineGamma(_ curve: DigitizedCurve) -> Double? { straightLine(curve)?.slope }
}
