import Foundation

/// Deterministic bounded Levenberg–Marquardt with a Nelder–Mead restart (docs/CONSTANTS.md).
struct LeastSquares {
    typealias Residuals = ([Double]) -> [Double]

    /// Cube root of machine epsilon (Nocedal & Wright §8.1); MINPACK ftol, xtol and gtol.
    static let jacobianRelativeStep = cbrt(Double.ulpOfOne)
    static let costTolerance = 1e-12
    static let stepTolerance = 1e-12
    static let gradientTolerance = 1e-12
    static let iterationLimit = 500
    /// Damping λ relative to diag(JᵀJ); past the limit the search has stalled.
    static let initialDamping = 1e-3
    static let dampingLimit = 1e16
    /// Starting simplex as a fraction of each parameter's box.
    static let simplexFraction = 0.1
    static let nelderMeadEvaluationsPerParameter = 2000

    enum Termination: String, Codable, Sendable {
        case exactFit, costChange, stepSize, gradient
        case iterationLimit, dampingLimit, singularSystem

        var converged: Bool { [.exactFit, .costChange, .stepSize, .gradient].contains(self) }
    }

    enum Path: String, Codable, Sendable {
        case levenbergMarquardt
        case nelderMeadThenLevenbergMarquardt
    }

    /// Standard errors are σ²·(JᵀJ)⁻¹ over free parameters: residual scatter, not digitizing error.
    struct Result: Sendable {
        let parameters: [Double]
        let residuals: [Double]
        let iterations: Int
        let termination: Termination
        let path: Path
        let nelderMeadEvaluations: Int
        /// nil on a bound, or for all when JᵀJ is singular or n ≤ p.
        let standardErrors: [Double?]
        let atBound: [Bool]
        let standardErrorNote: String?

        var rms: Double { residuals.rms }
    }

    let lower: [Double]
    let upper: [Double]
    let residuals: Residuals

    func minimize(from start: [Double]) -> Result {
        let first = levenbergMarquardt(from: clamped(start))
        guard !first.termination.converged else { return result(first, path: .levenbergMarquardt, evaluations: 0) }
        let search = nelderMead(from: first.parameters)
        let polish = levenbergMarquardt(from: search.parameters)
        if polish.termination.converged || polish.cost < first.cost {
            return result(polish, path: .nelderMeadThenLevenbergMarquardt, evaluations: search.evaluations)
        }
        return result(first, path: .levenbergMarquardt, evaluations: search.evaluations)
    }

    private struct Run {
        let parameters: [Double]
        let cost: Double
        let iterations: Int
        let termination: Termination
    }

    private func levenbergMarquardt(from start: [Double]) -> Run {
        var p = start
        var r = residuals(p)
        var cost = r.sumOfSquares
        var damping = Self.initialDamping
        var dampingGrowth = 2.0
        var iterations = 0
        var linearization: Linearization?

        func finish(_ termination: Termination) -> Run {
            Run(parameters: p, cost: cost, iterations: iterations, termination: termination)
        }

        while true {
            if cost == 0 { return finish(.exactFit) }
            if iterations >= Self.iterationLimit { return finish(.iterationLimit) }
            let current = linearization ?? linearize(at: p, residuals: r)
            linearization = current
            let free = current.free
            if free.contains(where: { current.normal[$0 * p.count + $0] == 0 }) { return finish(.singularSystem) }
            if free.isEmpty || current.maxCosine(residuals: r) <= Self.gradientTolerance { return finish(.gradient) }
            iterations += 1

            var damped = free.flatMap { i in free.map { current.normal[i * p.count + $0] } }
            for k in free.indices { damped[k * free.count + k] *= 1 + damping }
            guard let delta = NormalEquations.solve(damped, free.map { -current.gradient[$0] }) else {
                return finish(.singularSystem)
            }
            var trial = p
            for (k, i) in free.enumerated() { trial[i] = min(max(p[i] + delta[k], lower[i]), upper[i]) }
            let step = zip(trial, p).map { $0 - $1 }
            if step.norm <= Self.stepTolerance * (p.norm + Self.stepTolerance) { return finish(.stepSize) }

            let trialResiduals = residuals(trial)
            let trialCost = trialResiduals.sumOfSquares
            let actualReduction = cost - trialCost
            let predictedReduction = current.predictedReduction(step)
            let gainRatio = predictedReduction > 0 ? actualReduction / predictedReduction : -1
            let costBefore = cost
            if gainRatio > 0 {
                p = trial
                r = trialResiduals
                cost = trialCost
                damping *= max(1.0 / 3, 1 - pow(2 * gainRatio - 1, 3))
                dampingGrowth = 2
                linearization = nil
            } else {
                damping *= dampingGrowth
                dampingGrowth *= 2
                if damping > Self.dampingLimit { return finish(.dampingLimit) }
            }
            if abs(actualReduction) <= Self.costTolerance * costBefore && predictedReduction <= Self.costTolerance * costBefore
                && gainRatio <= 2
            {
                return finish(.costChange)
            }
        }
    }

    /// The Jacobian at a point, with JᵀJ, Jᵀr and the parameters free to move.
    private struct Linearization {
        let jacobianColumns: [[Double]]
        let normal: [Double]
        let gradient: [Double]
        let free: [Int]

        func maxCosine(residuals r: [Double]) -> Double {
            let residualNorm = r.norm
            return free.map { i in
                return abs(gradient[i]) / (jacobianColumns[i].norm * residualNorm)
            }.max() ?? 0
        }

        /// ‖r‖² − ‖r + J s‖², the reduction the linear model expects from step s.
        func predictedReduction(_ step: [Double]) -> Double {
            let count = step.count
            var curvature = 0.0
            for i in 0..<count { for j in 0..<count { curvature += step[i] * normal[i * count + j] * step[j] } }
            return -2 * gradient.dot(step) - curvature
        }
    }

    private func linearize(at p: [Double], residuals r: [Double]) -> Linearization {
        let columns = jacobianColumns(at: p)
        let count = p.count
        let normal = (0..<count).flatMap { i in (0..<count).map { columns[i].dot(columns[$0]) } }
        let gradient = columns.map { $0.dot(r) }
        let free = (0..<count).filter { i in
            !((p[i] <= lower[i] && gradient[i] > 0) || (p[i] >= upper[i] && gradient[i] < 0))
        }
        return Linearization(jacobianColumns: columns, normal: normal, gradient: gradient, free: free)
    }

    /// Central differences, one-sided where a bound is closer than the step.
    private func jacobianColumns(at p: [Double]) -> [[Double]] {
        p.indices.map { i in
            let h = Self.jacobianRelativeStep * max(abs(p[i]), 1)
            var high = p
            var low = p
            high[i] = min(p[i] + h, upper[i])
            low[i] = max(p[i] - h, lower[i])
            let span = high[i] - low[i]
            return zip(residuals(high), residuals(low)).map { ($0 - $1) / span }
        }
    }

    private func result(_ run: Run, path: Path, evaluations: Int) -> Result {
        let p = run.parameters
        let r = residuals(p)
        let atBound = p.indices.map { p[$0] <= lower[$0] || p[$0] >= upper[$0] }
        let free = p.indices.filter { !atBound[$0] }
        var errors = [Double?](repeating: nil, count: p.count)
        var note: String? = atBound.contains(true) ? "No standard error for parameters on a bound." : nil
        let degreesOfFreedom = r.count - free.count
        if degreesOfFreedom <= 0 {
            note = "No standard errors: \(r.count) residuals for \(free.count) free parameters."
        } else if !free.isEmpty {
            let columns = jacobianColumns(at: p)
            let normal = free.flatMap { i in free.map { columns[i].dot(columns[$0]) } }
            if let inverse = NormalEquations.inverse(normal, order: free.count) {
                let variance = r.sumOfSquares / Double(degreesOfFreedom)
                for (k, i) in free.enumerated() { errors[i] = (variance * inverse[k * free.count + k]).squareRoot() }
            } else {
                note = "No standard errors: JᵀJ is singular at the solution."
            }
        }
        return Result(
            parameters: p, residuals: r, iterations: run.iterations, termination: run.termination, path: path,
            nelderMeadEvaluations: evaluations, standardErrors: errors, atBound: atBound, standardErrorNote: note)
    }

    func clamped(_ p: [Double]) -> [Double] { p.clamped(lower: lower, upper: upper) }
}
