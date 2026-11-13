/// One traced curve of a datasheet chart: only the rows where the chart draws it, x ascending.
struct DigitizedCurve: Sendable, Equatable {
    let name: String
    let x: [Double]
    let y: [Double]

    /// What a curve is taken to be outside its samples.
    enum Edge: Sendable, Equatable {
        /// The end sample's value.
        case hold
        case zero
        /// Straight on from the end samples with these slopes (y per unit x).
        case slopes(below: Double, above: Double)
    }

    /// Linear interpolation between samples (across untraced gaps too), `edge` outside them.
    func value(at position: Double, edge: Edge) -> Double {
        guard let first = x.first, let last = x.last else { return 0 }
        if position < first || position > last {
            switch edge {
            case .hold: return position < first ? y[0] : y[y.count - 1]
            case .zero: return 0
            case .slopes(let below, let above):
                return position < first ? y[0] + below * (position - first) : y[y.count - 1] + above * (position - last)
            }
        }
        let upper = x.firstIndex { $0 >= position } ?? x.count - 1
        if x[upper] == position { return y[upper] }
        let fraction = (position - x[upper - 1]) / (x[upper] - x[upper - 1])
        return y[upper - 1] + fraction * (y[upper] - y[upper - 1])
    }

    func resampled(onto grid: [Double], edge: Edge) -> [Double] { grid.map { value(at: $0, edge: edge) } }
}
