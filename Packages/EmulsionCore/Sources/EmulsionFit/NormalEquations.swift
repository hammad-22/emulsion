/// Cholesky solves; plain Swift (LAPACK needs an unsafe flag here), bit-identical run to run.
enum NormalEquations {
    /// Pivot ÷ largest diagonal below this: singular to about 12 significant digits.
    static let relativePivotTolerance = 1e-12

    static func solve(_ a: [Double], _ b: [Double]) -> [Double]? {
        guard let lower = factor(a, order: b.count) else { return nil }
        return solve(lower: lower, b)
    }

    /// Weighted least squares through the normal equations; nil when they are singular.
    static func solveLeastSquares(columns: [[Double]], rhs: [Double], weights: [Double]? = nil) -> [Double]? {
        let weights = weights ?? [Double](repeating: 1, count: rhs.count)
        func weightedDot(_ a: [Double], _ b: [Double]) -> Double {
            weights.indices.reduce(0) { $0 + weights[$1] * a[$1] * b[$1] }
        }
        return solve(columns.flatMap { a in columns.map { weightedDot(a, $0) } }, columns.map { weightedDot($0, rhs) })
    }

    static func inverse(_ a: [Double], order: Int) -> [Double]? {
        guard let lower = factor(a, order: order) else { return nil }
        var inverse = [Double](repeating: 0, count: order * order)
        for column in 0..<order {
            var unit = [Double](repeating: 0, count: order)
            unit[column] = 1
            let x = solve(lower: lower, unit)
            for row in 0..<order { inverse[row * order + column] = x[row] }
        }
        // Symmetric in exact arithmetic; average away the rounding asymmetry.
        for row in 0..<order {
            for column in (row + 1)..<order {
                let mean = (inverse[row * order + column] + inverse[column * order + row]) / 2
                inverse[row * order + column] = mean
                inverse[column * order + row] = mean
            }
        }
        return inverse
    }

    static func factor(_ a: [Double], order n: Int) -> [Double]? {
        guard n > 0, a.count == n * n, a.allSatisfy(\.isFinite) else { return nil }
        let largestDiagonal = (0..<n).map { a[$0 * n + $0] }.max() ?? 0
        guard largestDiagonal > 0 else { return nil }
        let minimumPivot = relativePivotTolerance * largestDiagonal
        var lower = [Double](repeating: 0, count: n * n)
        for j in 0..<n {
            var pivot = a[j * n + j]
            for k in 0..<j { pivot -= lower[j * n + k] * lower[j * n + k] }
            guard pivot > minimumPivot else { return nil }
            let diagonal = pivot.squareRoot()
            lower[j * n + j] = diagonal
            for i in (j + 1)..<n {
                var sum = a[i * n + j]
                for k in 0..<j { sum -= lower[i * n + k] * lower[j * n + k] }
                lower[i * n + j] = sum / diagonal
            }
        }
        return lower
    }

    private static func solve(lower: [Double], _ b: [Double]) -> [Double] {
        let n = b.count
        var y = b
        for i in 0..<n {
            for k in 0..<i { y[i] -= lower[i * n + k] * y[k] }
            y[i] /= lower[i * n + i]
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for k in (i + 1)..<n { y[i] -= lower[k * n + i] * y[k] }
            y[i] /= lower[i * n + i]
        }
        return y
    }
}
