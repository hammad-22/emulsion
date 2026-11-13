import Foundation

/// Bounded nonlinear least squares: minimizes Σ rᵢ(p)² over `lower ≤ p ≤ upper`. Deterministic: no randomness,
/// no concurrency, so the same problem always gives bit-identical results.
///
/// Levenberg–Marquardt with Marquardt's diagonal damping and Nielsen's gain-ratio update; bounds hold by projecting
/// each step into the box, and a parameter on a bound whose gradient points outward is frozen for that step. When
/// it stops without converging (iteration or damping limit, singular system), a bounded Nelder–Mead search restarts
/// from its best point and Levenberg–Marquardt polishes once more.
struct LeastSquares {
    typealias Residuals = ([Double]) -> [Double]

    /// Central-difference step relative to max(|p|, 1): the cube root of machine epsilon (≈ 6e-6) balances
    /// truncation against rounding error (Nocedal & Wright, Numerical Optimization, 2nd ed., §8.1).
    static let jacobianRelativeStep = cbrt(Double.ulpOfOne)
    /// Converged when both the actual and the predicted relative cost reductions fall below this (MINPACK's ftol).
    static let costTolerance = 1e-12
    /// Converged when a step is shorter than this relative to |p| (MINPACK's xtol).
    static let stepTolerance = 1e-12
    /// Converged when every free Jacobian column is this close to orthogonal to the residuals (MINPACK's gtol, a cosine).
    static let gradientTolerance = 1e-12
    static let iterationLimit = 500
    /// Marquardt damping λ at the start, relative to diag(JᵀJ).
    static let initialDamping = 1e-3
    /// Past this the damped step is too short to matter: the search has stalled.
    static let dampingLimit = 1e16
    /// Nelder–Mead's starting simplex spans this fraction of each parameter's box.
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

    /// The solution and its fit statistics. Standard errors come from σ²·(JᵀJ)⁻¹ over the free parameters (those not on
    /// a bound, which are held fixed), with σ² = SSR / (n − p_free): they describe the scatter of the residuals around
    /// this model only, not the digitizing error of the data.
    struct Result: Sendable {
        let parameters: [Double]
        let residuals: [Double]
        /// Levenberg–Marquardt iterations of the run that produced `parameters`.
        let iterations: Int
        let termination: Termination
        let path: Path
        let nelderMeadEvaluations: Int
        /// nil for a parameter on a bound, or for all of them when JᵀJ is singular or n ≤ p.
        let standardErrors: [Double?]
        let atBound: [Bool]
        /// Why some standard errors are missing, when they are.
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

    // MARK: Levenberg–Marquardt

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

    /// The Jacobian at a point, with the normal matrix JᵀJ, the gradient Jᵀr and the parameters free to move.
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

    // MARK: Nelder–Mead

    /// Bounded by clamping every vertex into the box; standard coefficients (reflect 1, expand 2, contract and
    /// shrink ½). Ties are broken by vertex index, so the search is deterministic.
    private func nelderMead(from start: [Double]) -> (parameters: [Double], evaluations: Int) {
        let count = start.count
        let evaluationLimit = Self.nelderMeadEvaluationsPerParameter * count
        var evaluations = 0
        func cost(_ p: [Double]) -> Double {
            evaluations += 1
            let value = residuals(p).sumOfSquares
            return value.isNaN ? .infinity : value
        }
        var vertices = [start]
        for i in 0..<count {
            var vertex = start
            let step = Self.simplexFraction * (upper[i] - lower[i])
            vertex[i] = start[i] + step <= upper[i] ? start[i] + step : start[i] - step
            vertices.append(vertex)
        }
        var costs = vertices.map(cost)

        while evaluations < evaluationLimit {
            let order = costs.indices.sorted { (costs[$0], $0) < (costs[$1], $1) }
            let best = order[0]
            let worst = order[count]
            let secondWorst = order[count - 1]
            let size = vertices.map { zip($0, vertices[best]).map { $0 - $1 }.norm }.max() ?? 0
            if costs[worst] - costs[best] <= Self.costTolerance * costs[best]
                && size <= Self.stepTolerance * (vertices[best].norm + Self.stepTolerance)
            {
                break
            }
            let centroid = (0..<count).map { i in
                order.dropLast().reduce(0) { $0 + vertices[$1][i] } / Double(count)
            }
            func toward(_ target: [Double], _ factor: Double) -> [Double] {
                clamped(zip(centroid, target).map { $0 + factor * ($1 - $0) })
            }
            let reflected = toward(vertices[worst], -1)
            let reflectedCost = cost(reflected)
            if reflectedCost < costs[best] {
                let expanded = toward(vertices[worst], -2)
                let expandedCost = cost(expanded)
                (vertices[worst], costs[worst]) = expandedCost < reflectedCost ? (expanded, expandedCost) : (reflected, reflectedCost)
            } else if reflectedCost < costs[secondWorst] {
                (vertices[worst], costs[worst]) = (reflected, reflectedCost)
            } else {
                let outside = reflectedCost < costs[worst]
                let contracted = toward(outside ? reflected : vertices[worst], 0.5)
                let contractedCost = cost(contracted)
                if contractedCost < min(reflectedCost, costs[worst]) {
                    (vertices[worst], costs[worst]) = (contracted, contractedCost)
                } else {
                    for i in order.dropFirst() {
                        vertices[i] = zip(vertices[best], vertices[i]).map { $0 + 0.5 * ($1 - $0) }
                        costs[i] = cost(vertices[i])
                    }
                }
            }
        }
        let best = costs.indices.min { (costs[$0], $0) < (costs[$1], $1) } ?? 0
        return (vertices[best], evaluations)
    }

    // MARK: Statistics

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

    private func clamped(_ p: [Double]) -> [Double] { p.clamped(lower: lower, upper: upper) }
}
