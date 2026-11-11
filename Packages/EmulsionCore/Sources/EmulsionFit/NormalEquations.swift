/// Symmetric positive-definite systems (least-squares normal equations) by Cholesky factorization, A = L Lᵀ.
/// Matrices are n×n arrays, row-major. Plain Swift on purpose: the systems have at most a dozen unknowns, and
/// Accelerate's current LAPACK interface would need an unsafe compiler flag in this package. Fixed loop order,
/// so results are bit-identical run to run.
enum NormalEquations {
    /// A pivot (the squared diagonal of L) smaller than this fraction of A's largest diagonal entry means a column is,
    /// to about 12 significant digits, a combination of the earlier ones: the matrix counts as singular.
    static let relativePivotTolerance = 1e-12

    /// Solves A x = b, or nil when A is singular or not positive definite.
    static func solve(_ a: [Double], _ b: [Double]) -> [Double]? {
        guard let lower = factor(a, order: b.count) else { return nil }
        return solve(lower: lower, b)
    }

    /// A⁻¹, or nil when A is singular or not positive definite.
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

    /// L, row-major, or nil when a pivot fails the tolerance (or the input isn't a finite square matrix).
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
