import CoreImage
import EmulsionCore
import Foundation
import Testing

/// Grain in the visual regression suite (MOV-37): goldens are grain-free, and grain is checked as
/// statistics of the L* residual against `Goldens/grain-statistics.json` (`GrainStatistics`).
/// Named `VisualRegression…` so `swift test --filter VisualRegression` updates it with the goldens.
struct VisualRegressionGrainTests {
    @Test func grainStatisticsMatchReference() throws {
        let items = RegressionCase.grainCases.map { c in GrainStatistics.Item(name: c.name) { try Self.measure(c) } }
        try GrainStatistics.run(
            items, store: .repository, reportDirectory: VisualRegression.reportDirectory, regenerate: VisualRegression.regenerateCommand)
    }

    /// Renders the case with and without grain, everything else unchanged.
    static func measure(_ c: RegressionCase, grain: Double? = nil, seed: Double? = nil) throws -> GrainStatistics {
        let (grainy, clean) = try renders(c, grain: grain, seed: seed)
        return GrainStatistics(grainy: grainy, clean: clean)
    }

    private static func renders(_ c: RegressionCase, grain: Double? = nil, seed: Double? = nil) throws -> (
        grainy: RegressionImage, clean: RegressionImage
    ) {
        let scene = try c.scene()
        var adjustments = c.adjustments
        if let grain { adjustments.grain = grain }
        if let seed { adjustments.seed = seed }
        return (
            try VisualRegression.render(scene, adjustments, contract: c.contract),
            try VisualRegression.render(scene, c.goldenAdjustments, contract: c.contract)
        )
    }

    /// An entry no grain case measures is never checked.
    @Test func everyGrainReferenceBelongsToAGrainCase() throws {
        let names = RegressionCase.grainCases.map(\.name)
        #expect(Set(names).count == names.count, "duplicate grain case names")
        let references = try #require(try GrainStatistics.references(in: VisualRegression.Store.repository.readDirectory))
        for name in references.keys.sorted() {
            #expect(names.contains(name), "\(GrainStatistics.referenceFileName) entry \(name) belongs to no grain case")
        }
    }

    // MARK: The check is not vacuous

    /// 5% less grain must fail on sd; another seed (a different pattern of the same grain) must pass.
    @Test func aSmallGrainChangeFailsAndASeedChangePasses() throws {
        let c = try RegressionCase.named("gradient.grain")
        let reference = try Self.measure(c)
        let lessGrain = try Self.measure(c, grain: 0.95)
        let otherSeed = try Self.measure(c, seed: 4)
        for (label, s) in [("grain 1.0 seed 3", reference), ("grain 0.95", lessGrain), ("seed 4", otherSeed)] {
            print(String(format: "grain sensitivity %@: mean %.6f sd %.6f corr %.6f", label, s.mean, s.sd, s.neighbourCorrelation))
        }
        #expect(lessGrain.mismatches(against: reference).contains("sd"), "grain 0.95 passes: \(lessGrain) vs \(reference)")
        #expect(otherSeed.mismatches(against: reference).isEmpty, "seed 4 fails: \(otherSeed) vs \(reference)")
    }

    // MARK: The CI failure

    /// What broke the pixel-for-pixel grain goldens on GitHub's runner: a few isolated pixels whose
    /// grain is far outside the range seen locally. It fails the golden thresholds and must pass the
    /// statistics.
    @Test func isolatedFlippedPixelsStayInsideTheTolerances() throws {
        let c = try RegressionCase.named("iphone12pro-proraw.graded")
        let (grainy, clean) = try Self.renders(c)
        let flippedCount = 15
        // About 5 L* in encoded Display P3 (its sRGB curve tracks L* / 100 closely), more than
        // the 4.67 ΔE00 seen on CI.
        let step = Int(0.05 * RegressionImage.maxCode)
        let stride = grainy.pixels.count / flippedCount
        var pixels = grainy.pixels
        for i in 0..<flippedCount {
            let index = i * stride + stride / 2 + grainy.width / 2
            let shift = i.isMultiple(of: 2) ? step : -step
            let p = SIMD3<Int>(truncatingIfNeeded: pixels[index]) &+ shift
            pixels[index] = SIMD3(UInt16(clamping: p.x), UInt16(clamping: p.y), UInt16(clamping: p.z))
        }
        let flipped = RegressionImage(width: grainy.width, height: grainy.height, pixels: pixels)

        let lightnessShift =
            zip(grainy.encoded, flipped.encoded).map {
                abs(ColorDifference.lab(fromDisplayP3: $0).x - ColorDifference.lab(fromDisplayP3: $1).x)
            }.max() ?? 0
        let golden = try #require(VisualRegression.compare(grainy, flipped)).summary
        let before = GrainStatistics(grainy: grainy, clean: clean)
        let after = GrainStatistics(grainy: flipped, clean: clean)
        print(
            String(
                format: "flipped %d of %d pixels, max ΔL* %.3f; golden ΔE00 mean %.4f p95 %.4f max %.4f",
                flippedCount, grainy.pixels.count, lightnessShift, golden.mean, golden.p95, golden.max))
        print(
            String(
                format: "grain statistics before mean %.6f sd %.6f corr %.6f; after mean %.6f sd %.6f (%+.3f%%) corr %.6f",
                before.mean, before.sd, before.neighbourCorrelation, after.mean, after.sd, 100 * (after.sd / before.sd - 1),
                after.neighbourCorrelation))
        #expect(!VisualRegression.thresholds.accepts(golden), "the flipped pixels pass the golden thresholds: \(golden)")
        #expect(after.mismatches(against: before).isEmpty, "\(after) vs \(before)")
    }

    // MARK: Harness

    @Test func missingEntriesFailAndUpdatesWriteOnlyWhatChanged() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grain-statistics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VisualRegression.Store.local(directory)
        let statistics = GrainStatistics(mean: 0.01, sd: 2, neighbourCorrelation: 0.5)
        let items = [GrainStatistics.Item(name: "a") { statistics }]
        func run(_ mode: VisualRegression.UpdateMode) throws {
            try GrainStatistics.run(items, store: store, reportDirectory: directory, regenerate: "regenerate", mode: mode, isCI: false)
        }
        try GrainStatistics.write(["orphan": statistics], to: directory)

        try withKnownIssue {
            try run(.none)
        } matching: {
            $0.comments.contains { $0.rawValue.contains("a: grain statistics no reference") }
        }
        try run(.failing)
        #expect(try GrainStatistics.references(in: directory) == ["a": statistics])
        let report = try String(contentsOf: directory.appending(path: GrainStatistics.reportFileName), encoding: .utf8)
        #expect(report.contains("| a |") && report.contains("| new |") && report.contains("orphan"), "\(report)")

        let written = try Data(contentsOf: directory.appending(path: GrainStatistics.referenceFileName))
        try run(.failing)
        #expect(try Data(contentsOf: directory.appending(path: GrainStatistics.referenceFileName)) == written)
        try run(.none)

        withKnownIssue {
            try GrainStatistics.run(items, store: store, reportDirectory: directory, regenerate: "r", mode: .failing, isCI: true)
        }
    }
}
