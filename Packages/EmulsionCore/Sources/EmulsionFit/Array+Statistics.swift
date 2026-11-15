/// Fixed summation order, so results are bit-identical run to run.
extension Array where Element == Double {
    func dot(_ other: [Double]) -> Double { zip(self, other).reduce(0) { $0 + $1.0 * $1.1 } }

    var sumOfSquares: Double { dot(self) }

    var rms: Double { (sumOfSquares / Double(Swift.max(count, 1))).squareRoot() }

    var maxAbs: Double { map(abs).max() ?? 0 }

    var norm: Double { sumOfSquares.squareRoot() }

    func clamped(lower: [Double], upper: [Double]) -> [Double] {
        indices.map { Swift.min(Swift.max(self[$0], lower[$0]), upper[$0]) }
    }
}
