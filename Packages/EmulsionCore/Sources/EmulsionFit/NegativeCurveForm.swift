import EmulsionCore
import Foundation

/// A curve form fitted to one layer's neutral-scale dye amounts, as a function of log10 exposure x relative to mid-gray.
/// Each form carries a small offset d0 (fitted, never stored: a constant per-layer density is absorbed by the
/// calibrated printer lights).
///
/// - `toeShoulder`: d0 + `FilmModel.negativeDyeAmount`, the engine's own curve. Written to the stock.
/// - `logistic`: d0 + range·logistic(4·gamma/range·(x − center)), the engine's previous negative curve. Comparison
///   only, never written to a stock.
enum NegativeCurveForm: String, CaseIterable, Codable, Sendable {
    case toeShoulder, logistic

    /// Dye amounts above minimum density, so the offset stays small: it only absorbs where the lowest traced density
    /// sits relative to the curve's own floor.
    static let offsetBounds = -0.1...0.1
    /// The symmetric logistic's long toe runs below the data's floor, so its offset needs more room downward to fit at
    /// all (it is then not a floor of anything); with `offsetBounds` it sits on the bound and fits worse.
    static let logisticOffsetBounds = -1.0...0.1
    /// Brackets camera-negative straight-line slopes (around 0.5–0.6 per log10 exposure) with a wide margin.
    static let gammaBounds = 0.2...1.5
    /// The toe lies below mid-gray, within the 4 log10 the charts trace below it.
    static let toeExposureBounds = -4.0...0.0
    /// From a sharp corner to a bend spanning most of a chart.
    static let toeWidthBounds = 0.02...1.5
    /// The shoulder lies above mid-gray, near or beyond the top of the traced data (about +2.4 log10 on 250D).
    static let shoulderExposureBounds = 0.5...6.0
    static let shoulderWidthBounds = 0.02...2.0
    /// The logistic's density span: from less than the traced span to so wide it is nearly straight across a chart.
    static let rangeBounds = 0.5...8.0
    /// The logistic's centre, up to 4 log10 under and 6 over mid-gray: the charts span under 5 log10 in all.
    static let centerBounds = -4.0...6.0

    /// The shoulder bends only at the top of the traced data, so its fit starts this far past the last sample, in log10
    /// exposure, and moves inward (on 250D and 500T it ends 0.4–1.0 stops below the last sample).
    static let shoulderStartBeyondData = 0.5
    /// Starting shoulder width: a typical fitted toe width (0.2–0.3 log10 on 250D and 500T).
    static let shoulderWidthStart = 0.3

    var parameterNames: [String] {
        switch self {
        case .toeShoulder: ["offset", "gamma", "toeExposure", "toeWidth", "shoulderExposure", "shoulderWidth"]
        case .logistic: ["offset", "gamma", "range", "center"]
        }
    }

    var bounds: [ClosedRange<Double>] {
        switch self {
        case .toeShoulder:
            [
                Self.offsetBounds, Self.gammaBounds, Self.toeExposureBounds, Self.toeWidthBounds, Self.shoulderExposureBounds,
                Self.shoulderWidthBounds,
            ]
        case .logistic: [Self.logisticOffsetBounds, Self.gammaBounds, Self.rangeBounds, Self.centerBounds]
        }
    }

    /// Dye amount at log10 exposure `x` relative to mid-gray, offset included.
    func dyeAmount(_ p: [Double], at x: Double) -> Double {
        switch self {
        case .toeShoulder:
            p[0]
                + FilmModel.negativeDyeAmount(
                    logExposure: x, gamma: p[1], toeExposure: p[2], toeWidth: p[3], shoulderExposure: p[4], shoulderWidth: p[5])
        case .logistic:
            p[0] + p[2] / (1 + exp(-4 * p[1] / p[2] * (x - p[3])))
        }
    }

    /// Read off the data (x relative to mid-gray): the straight line through the middle third of the dye-amount span
    /// gives gamma and, where it meets zero, the toe; the toe width is what makes the curve pass through the data there
    /// (the form gives gamma·width·ln 2 at the toe). The logistic starts at the traced span, centred where the data cross
    /// half of it.
    func startingPoint(_ curve: DigitizedCurve) -> [Double] {
        let line = NegativeFit.straightLine(curve) ?? (slope: 1, intercept: 0)
        let gamma = line.slope
        let start: [Double]
        switch self {
        case .toeShoulder:
            let toe = -line.intercept / gamma
            let toeWidth = curve.value(at: toe, edge: .hold) / (gamma * log(2))
            start = [0, gamma, toe, toeWidth, (curve.x.last ?? 0) + Self.shoulderStartBeyondData, Self.shoulderWidthStart]
        case .logistic:
            let low = curve.y.min() ?? 0
            let span = (curve.y.max() ?? 0) - low
            let crossing = curve.x.indices.first { curve.y[$0] >= low + span / 2 }.map { curve.x[$0] } ?? 0
            start = [0, gamma, span, crossing]
        }
        return start.clamped(lower: bounds.map(\.lowerBound), upper: bounds.map(\.upperBound))
    }
}
