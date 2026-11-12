import Testing

@testable import EmulsionFit

struct NormalEquationsTests {
    /// A = [[4, 2, 2], [2, 5, 3], [2, 3, 6]] is positive definite; with x = [1, −2, 3], b = A x = [6, 1, 14].
    static let spd: [Double] = [4, 2, 2, 2, 5, 3, 2, 3, 6]

    @Test func solvesAKnownSystem() throws {
        let x = try #require(NormalEquations.solve(Self.spd, [6, 1, 14]))
        for (value, expected) in zip(x, [1.0, -2, 3]) { #expect(abs(value - expected) < 1e-13) }
    }

    @Test func inverseTimesMatrixIsIdentity() throws {
        let inverse = try #require(NormalEquations.inverse(Self.spd, order: 3))
        for row in 0..<3 {
            for column in 0..<3 {
                let product = (0..<3).reduce(0) { $0 + inverse[row * 3 + $1] * Self.spd[$1 * 3 + column] }
                #expect(abs(product - (row == column ? 1 : 0)) < 1e-13)
            }
            for column in 0..<3 { #expect(inverse[row * 3 + column] == inverse[column * 3 + row]) }
        }
    }

    @Test func singularMatrixHasNoSolution() {
        // Third row = first + second.
        let singular: [Double] = [1, 2, 3, 2, 5, 7, 3, 7, 10]
        #expect(NormalEquations.solve(singular, [1, 1, 1]) == nil)
        #expect(NormalEquations.inverse(singular, order: 3) == nil)
    }

    @Test func nearlySingularMatrixFailsThePivotTest() {
        let epsilon = NormalEquations.relativePivotTolerance / 10
        #expect(NormalEquations.solve([1, 1, 1, 1 + epsilon], [1, 1]) == nil)
    }

    @Test func indefiniteMatrixIsRejected() {
        #expect(NormalEquations.solve([1, 2, 2, 1], [1, 1]) == nil)
        #expect(NormalEquations.solve([-1, 0, 0, 1], [1, 1]) == nil)
    }

    @Test func sameInputGivesBitIdenticalOutput() throws {
        let first = try #require(NormalEquations.inverse(Self.spd, order: 3))
        let second = try #require(NormalEquations.inverse(Self.spd, order: 3))
        #expect(first.map(\.bitPattern) == second.map(\.bitPattern))
    }
}
