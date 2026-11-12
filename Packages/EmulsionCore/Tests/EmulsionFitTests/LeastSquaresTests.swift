import Foundation
import Testing

@testable import EmulsionFit

struct LeastSquaresTests {
    static let unbounded = 1e6

    static func solver(_ count: Int, lower: Double = -unbounded, upper: Double = unbounded, _ residuals: @escaping LeastSquares.Residuals)
        -> LeastSquares
    {
        LeastSquares(lower: Array(repeating: lower, count: count), upper: Array(repeating: upper, count: count), residuals: residuals)
    }

    static let xs = (0..<20).map { Double($0) / 4 }

    @Test func recoversAQuadratic() {
        let truth = [0.7, -1.3, 0.25]
        let ys = Self.xs.map { truth[0] + truth[1] * $0 + truth[2] * $0 * $0 }
        let result = Self.solver(3) { p in zip(Self.xs, ys).map { $1 - (p[0] + p[1] * $0 + p[2] * $0 * $0) } }.minimize(from: [0, 0, 0])
        #expect(result.termination.converged)
        #expect(result.path == .levenbergMarquardt)
        for (fitted, expected) in zip(result.parameters, truth) { #expect(abs(fitted - expected) < 1e-9) }
    }

    @Test func recoversAnExponential() {
        let truth = [2.5, -0.8]
        let ys = Self.xs.map { truth[0] * exp(truth[1] * $0) }
        let result = Self.solver(2) { p in zip(Self.xs, ys).map { $1 - p[0] * exp(p[1] * $0) } }.minimize(from: [1, 0])
        #expect(result.termination.converged)
        for (fitted, expected) in zip(result.parameters, truth) { #expect(abs(fitted - expected) < 1e-9) }
    }

    @Test func optimumOutsideTheBoxEndsOnTheBound() {
        // Unbounded optimum (3, −2); the box allows p₀ ≤ 1 and p₁ ≥ −1.
        let solver = LeastSquares(lower: [-5, -1], upper: [1, 5]) { p in [p[0] - 3, p[1] + 2, 0.1 * (p[0] + p[1])] }
        let result = solver.minimize(from: [0, 0])
        #expect(result.termination.converged)
        #expect(result.parameters == [1, -1])
        #expect(result.atBound == [true, true])
        #expect(result.standardErrors.allSatisfy { $0 == nil })
    }

    @Test func rosenbrockConverges() {
        let result = Self.solver(2) { p in [10 * (p[1] - p[0] * p[0]), 1 - p[0]] }.minimize(from: [-1.2, 1])
        #expect(result.termination.converged)
        #expect(abs(result.parameters[0] - 1) < 1e-8 && abs(result.parameters[1] - 1) < 1e-8)
    }

    @Test func flatStartFallsBackToNelderMead() {
        // Zero gradient at the start makes the damped system singular; the plateau ends at 0.2.
        let result = LeastSquares(lower: [0], upper: [4]) { p in [p[0] <= 0.2 ? 2 : p[0] - 2] }.minimize(from: [0])
        #expect(result.path == .nelderMeadThenLevenbergMarquardt)
        #expect(result.nelderMeadEvaluations > 0)
        #expect(result.termination.converged)
        #expect(abs(result.parameters[0] - 2) < 1e-9)
    }

    @Test func standardErrorsMatchTheLinearTheory() throws {
        // Straight line through noisy points: SE(slope) = σ / √Σ(x − x̄)².
        let noise = [0.03, -0.02, 0.01, -0.04, 0.02, 0.0, -0.01, 0.03]
        let x = noise.indices.map(Double.init)
        let y = zip(x, noise).map { 1 + 0.5 * $0 + $1 }
        let result = Self.solver(2) { p in zip(x, y).map { $1 - p[0] - p[1] * $0 } }.minimize(from: [0, 0])
        let mean = x.reduce(0, +) / Double(x.count)
        let sigma = (result.residuals.sumOfSquares / Double(x.count - 2)).squareRoot()
        let expected = sigma / x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }.squareRoot()
        let slopeError = try #require(result.standardErrors[1])
        #expect(abs(slopeError - expected) < 1e-6 * expected)
    }

    /// A parameter held on its bound is fixed: its standard errors and degrees of freedom match the model without it.
    @Test func boundParameterCountsAsFixedForStandardErrors() throws {
        let noise = [0.03, -0.02, 0.01, -0.04, 0.02, 0.0, -0.01, 0.03, -0.02, 0.01]
        let x = noise.indices.map(Double.init)
        let y = zip(x, noise).map { 1 + 0.5 * $0 + 0.02 * $0 * $0 + $1 }
        // The curvature wants to be positive; an upper bound of 0 holds it at 0.
        let bounded = LeastSquares(lower: [-10, -10, -1], upper: [10, 10, 0]) { p in
            zip(x, y).map { $1 - p[0] - p[1] * $0 - p[2] * $0 * $0 }
        }.minimize(from: [0, 0, -0.5])
        let line = Self.solver(2) { p in zip(x, y).map { $1 - p[0] - p[1] * $0 } }.minimize(from: [0, 0])
        #expect(bounded.atBound == [false, false, true])
        for i in 0..<2 {
            let withBound = try #require(bounded.standardErrors[i])
            let without = try #require(line.standardErrors[i])
            #expect(abs(withBound - without) <= 1e-9 * without)
        }
    }

    @Test func identicalInputsGiveBitIdenticalResults() {
        let run = { Self.solver(2) { p in [10 * (p[1] - p[0] * p[0]), 1 - p[0]] }.minimize(from: [-1.2, 1]) }
        let first = run()
        let second = run()
        #expect(first.parameters.map(\.bitPattern) == second.parameters.map(\.bitPattern))
        #expect(first.residuals.map(\.bitPattern) == second.residuals.map(\.bitPattern))
        #expect(first.iterations == second.iterations)
    }
}
