extension LeastSquares {
    /// The standard Nelder–Mead coefficients.
    private static let reflection = 1.0, expansion = 2.0, contraction = 0.5, shrink = 0.5

    /// Bounded by clamping every vertex into the box. Ties are broken by vertex index, so the search
    /// is deterministic.
    func nelderMead(from start: [Double]) -> (parameters: [Double], evaluations: Int) {
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
            let reflected = toward(vertices[worst], -Self.reflection)
            let reflectedCost = cost(reflected)
            if reflectedCost < costs[best] {
                let expanded = toward(vertices[worst], -Self.expansion)
                let expandedCost = cost(expanded)
                (vertices[worst], costs[worst]) = expandedCost < reflectedCost ? (expanded, expandedCost) : (reflected, reflectedCost)
            } else if reflectedCost < costs[secondWorst] {
                (vertices[worst], costs[worst]) = (reflected, reflectedCost)
            } else {
                let outside = reflectedCost < costs[worst]
                let contracted = toward(outside ? reflected : vertices[worst], Self.contraction)
                let contractedCost = cost(contracted)
                if contractedCost < min(reflectedCost, costs[worst]) {
                    (vertices[worst], costs[worst]) = (contracted, contractedCost)
                } else {
                    for i in order.dropFirst() {
                        vertices[i] = zip(vertices[best], vertices[i]).map { $0 + Self.shrink * ($1 - $0) }
                        costs[i] = cost(vertices[i])
                    }
                }
            }
        }
        let best = costs.indices.min { (costs[$0], $0) < (costs[$1], $1) } ?? 0
        return (vertices[best], evaluations)
    }
}
