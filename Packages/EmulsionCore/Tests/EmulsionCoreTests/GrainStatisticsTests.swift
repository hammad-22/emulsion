import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionCore

/// RMS granularity and noise power of the grain cases (MOV-146). The engine's numbers are tracked,
/// not gated: they go to `grain-statistics.md` / `.json` in the visual regression report directory
/// (a CI artifact), so a grain change shows up as a diff of those numbers. Only properties every
/// grain model must have are checked.
struct GrainStatisticsTests {
    // MARK: The measurements

    /// SplitMix64 (Steele, Lea & Flood 2014): deterministic noise for the metric checks.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Uniform noise of standard deviation `sigma` around density 1.
    private static func whiteNoise(width: Int, height: Int, sigma: Double, seed: UInt64) -> [Double] {
        var generator = SplitMix(state: seed)
        let halfWidth = sigma * 3.0.squareRoot()
        return (0..<width * height).map { _ in 1 + Double.random(in: -halfWidth...halfWidth, using: &generator) }
    }

    /// White noise: σ(D) is the noise's own, and its power is flat at σ² (Parseval).
    @Test func whiteNoiseHasFlatPowerEqualToItsVariance() {
        let (width, height, sigma) = (256, 256, 0.05)
        let patch = GrainStatistics.Patch(
            densities: Self.whiteNoise(width: width, height: height, sigma: sigma, seed: 1), width: width, height: height)
        #expect(abs(patch.meanDensity - 1) < 0.001)
        #expect(abs(patch.rmsDensity - sigma) < 0.001)
        for (k, power) in patch.noisePower.enumerated().dropFirst() {
            #expect(abs(power / (sigma * sigma) - 1) < 0.25, "bin \(k): \(power)")
        }
        #expect(abs(patch.highToLowPower - 1) < 0.1)
    }

    /// Grain two pixels wide (each value repeated in 2 × 2 blocks) moves its power to low frequencies.
    @Test func coarserGrainMovesPowerToLowFrequencies() {
        let (width, height) = (256, 256)
        let fine = Self.whiteNoise(width: width / 2, height: height / 2, sigma: 0.05, seed: 2)
        let coarse = (0..<width * height).map { i in fine[(i / width / 2) * (width / 2) + (i % width) / 2] }
        let patch = GrainStatistics.Patch(densities: coarse, width: width, height: height)
        #expect(abs(patch.rmsDensity - 0.05) < 0.002)
        #expect(patch.highToLowPower < 0.25)
    }

    // MARK: The engine's grain

    /// Flat patches this wide, so a grain cell is about 1.7 px as at 4032 px (`FilmLook.grainCell`
    /// is a fraction of the long edge; sub-pixel grain averages away).
    static let patchWidth = 2400
    static let patchHeight = 128
    static let exposures: [Double] = [-4, -3, -2, -1, 0, 1, 2, 3, 4]

    /// The grain cases of the regression suite.
    static let cases = ["gradient.grain", "gradient.default-look", "pixel8pro-dng.graded"]

    struct Tracked: Codable {
        let caseName: String
        let grain: Double
        /// One per `GrainStatisticsTests.exposures`.
        let patches: [GrainStatistics.Patch]
    }

    private static func measure(_ adjustments: Adjustments) throws -> [GrainStatistics.Patch] {
        try exposures.map { stops in
            let scene = SceneFixtures.flat(Float(0.18 * pow(2, stops)), width: patchWidth, height: patchHeight)
            let rendered = try VisualRegression.renderer.render(Negative(image: scene, contract: .sceneReferred), adjustments)
            return GrainStatistics.patch(RegressionImage(rendering: rendered))
        }
    }

    @Test func tracksTheGrainCases() throws {
        let midGray = try #require(Self.exposures.firstIndex(of: 0))
        let clean = try Self.measure(.neutral)
        #expect(clean.allSatisfy { $0.rmsDensity < 0.001 }, "grain off: \(clean.map(\.rmsDensity))")
        var tracked: [Tracked] = []
        for name in Self.cases {
            let adjustments = try RegressionCase.named(name).adjustments
            let patches = try Self.measure(adjustments)
            #expect(patches[midGray].rmsDensity > 0.005, "\(name): grain not measurable at mid-gray")
            tracked.append(Tracked(caseName: name, grain: adjustments.grain, patches: patches))
        }
        let byGrain = tracked.sorted { $0.grain < $1.grain }.map { $0.patches[midGray].rmsDensity }
        #expect(byGrain == byGrain.sorted(), "σ(D) at mid-gray does not rise with the grain amount: \(byGrain)")
        try Self.write(tracked, to: VisualRegression.reportDirectory)
    }

    private struct Document: Codable {
        let exposureStops: [Double]
        let cases: [Tracked]
    }

    private static func write(_ tracked: [Tracked], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Document(exposureStops: exposures, cases: tracked))
            .write(to: directory.appending(path: "grain-statistics.json"))
        var lines = [
            "### Grain statistics", "",
            "Visual density D = −log10(display luminance) of flat \(patchWidth) × \(patchHeight) patches; σ(D) per pixel; "
                + "high/low = noise power at 0.375–0.5 over 0.016–0.125 cycles per pixel (1 = white).", "",
            "| Case | Grain | Stops | Mean D | σ(D) | High/low |", "| --- | ---: | ---: | ---: | ---: | ---: |",
        ]
        for t in tracked {
            for (stops, p) in zip(exposures, t.patches) {
                lines.append(
                    String(
                        format: "| %@ | %.2f | %+.0f | %.3f | %.4f | %.3f |", t.caseName, t.grain, stops, p.meanDensity, p.rmsDensity,
                        p.highToLowPower))
            }
        }
        try ReportFiles(directory: directory).write(lines.joined(separator: "\n") + "\n", to: "grain-statistics.md")
    }
}
