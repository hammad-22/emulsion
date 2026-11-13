import CoreImage
import CryptoKit
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Renders fixed scenes with fixed adjustments and compares them with committed goldens in
/// CIEDE2000 (MOV-37). It detects change; it does not prove the look is right.
struct VisualRegressionTests {
    @Test func rendersMatchGoldens() throws {
        let items = RegressionCase.all.map { c in
            VisualRegression.Item(name: c.name, thresholds: c.thresholds) {
                try VisualRegression.render(c.scene(), c.adjustments, contract: c.contract)
            }
        }
        try VisualRegression.run(
            "goldens", items, store: .repository, reportDirectory: VisualRegression.reportDirectory,
            regenerate:
                "EMULSION_UPDATE_GOLDENS=1 swift test --filter VisualRegression, review the summary, commit the goldens with the change.")
    }

    // MARK: The suite is not vacuous

    /// Small, real edits must fail the thresholds: the case rendered as is vs with the edit, so the
    /// check does not depend on the committed goldens.
    @Test(arguments: [("chart24.neutral", 0.1, 0.0), ("chart24.neutral", 0, 0.2), ("wedge.neutral", 0.1, 0)])
    func smallEditsFailTheThresholds(name: String, exposure: Double, warmth: Double) throws {
        let regressionCase = try RegressionCase.named(name)
        let scene = try regressionCase.scene()
        var adjustments = regressionCase.adjustments
        adjustments.exposure += exposure
        adjustments.warmth += warmth
        let edit = "exposure +\(exposure), warmth +\(warmth)"
        let summary = try #require(
            VisualRegression.compare(
                VisualRegression.render(scene, regressionCase.adjustments), VisualRegression.render(scene, adjustments))
        ).summary
        print(String(format: "sensitivity %@ %@: mean %.4f p95 %.4f max %.4f", name, edit, summary.mean, summary.p95, summary.max))
        #expect(!VisualRegression.thresholds.accepts(summary), "\(name) with \(edit) passes: \(summary)")
    }

    /// ΔE00 misses grain: on a photo, losing the grain or changing its seed stays inside every
    /// ΔE00 limit and only the structural check fails (numbers on `VisualRegression.photoThresholds`).
    @Test(arguments: ["iphone12pro-proraw.default-look", "pixel8pro-dng.default-look"])
    func grainChangesFailOnlyTheStructuralCheck(name: String) throws {
        let regressionCase = try RegressionCase.named(name)
        let negative = Negative(image: try regressionCase.scene(), contract: .sceneReferred)
        let reference = RegressionImage(rendering: try VisualRegression.renderer.render(negative, regressionCase.adjustments))
        for (edit, change) in [("no grain", { (a: inout Adjustments) in a.grain = 0 }), ("seed +1", { $0.seed += 1 })] {
            var adjustments = regressionCase.adjustments
            change(&adjustments)
            let edited = RegressionImage(rendering: try VisualRegression.renderer.render(negative, adjustments))
            let comparison = try #require(VisualRegression.compare(reference, edited, structure: true))
            let ssim = try #require(comparison.structuralSimilarity)
            print(String(format: "structure %@ %@: SSIM %.5f, ΔE00 max %.3f", name, edit, ssim, comparison.summary.max))
            #expect(VisualRegression.thresholds.accepts(comparison.summary), "\(name) \(edit): ΔE00 alone already fails")
            #expect(!VisualRegression.photoThresholds.accepts(comparison.summary, structuralSimilarity: ssim), "\(name) \(edit) passes")
        }
    }

    /// The CI outliers of #31 (about 16 isolated pixels moved ≈ 4 ΔE00), simulated on the photo
    /// local-tone goldens, pass their structural floor.
    @Test(arguments: ["iphone12pro-proraw.localtone", "pixel8pro-dng.localtone"])
    func isolatedOutliersPassThePhotoLocalToneStructuralFloor(name: String) throws {
        let golden = try #require(VisualRegression.Store.repository.golden(name)).get()
        let outliers = 16
        let lift = UInt16(0.042 * RegressionImage.maxCode)
        var pixels = golden.pixels
        for i in stride(from: pixels.count / (2 * outliers), to: pixels.count, by: pixels.count / outliers) {
            pixels[i] = pixels[i] &+ SIMD3(repeating: min(lift, UInt16.max - pixels[i].max()))
        }
        let comparison = try #require(
            VisualRegression.compare(golden, RegressionImage(width: golden.width, height: golden.height, pixels: pixels), structure: true))
        print(
            String(format: "outliers %@: SSIM %.5f, ΔE00 max %.2f", name, comparison.structuralSimilarity ?? .nan, comparison.summary.max))
        #expect(comparison.summary.max > VisualRegression.thresholds.max)
        #expect(
            VisualRegression.photoLocalToneThresholds.accepts(comparison.summary, structuralSimilarity: comparison.structuralSimilarity))
    }

    /// A golden no case renders is never checked; delete it rather than let it look covered.
    @Test func everyGoldenBelongsToACase() throws {
        let names = RegressionCase.all.map(\.name)
        #expect(Set(names).count == names.count, "duplicate case names")
        let goldens = try #require(VisualRegression.Store.repository.readDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: goldens, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "png" {
            let name = file.deletingPathExtension().lastPathComponent
            #expect(
                names.contains(name),
                "\(name).png belongs to no case: delete \(VisualRegression.sourceGoldens.appending(path: file.lastPathComponent).path)")
        }
    }

    /// The CI failure (hammad-22/emulsion#31): 15 isolated pixels of 43,200 up to 4.67 ΔE00 off
    /// fail the strict thresholds and pass the photo local-tone ones; two pixels in a thousand fail both.
    /// ΔE00 only (structure passes here); the SSIM side is `isolatedOutliersPassThePhotoLocalToneStructuralFloor`.
    @Test func isolatedOutliersPassOnlyThePhotoLocalToneThresholds() {
        let pixelCount = 43_200
        func summary(outliers: Int) -> ColorDifference.Summary {
            ColorDifference.Summary((0..<pixelCount).map { $0 < outliers ? 4.67 : 0.005 })
        }
        let seenOnCI = summary(outliers: 15)
        let localTone = VisualRegression.photoLocalToneThresholds
        #expect(!VisualRegression.thresholds.accepts(seenOnCI))
        #expect(localTone.accepts(seenOnCI, structuralSimilarity: 1))
        #expect(!localTone.accepts(summary(outliers: pixelCount / 500), structuralSimilarity: 1))
        #expect(!localTone.accepts(seenOnCI), "a photo case without SSIM must fail")
    }

    // MARK: Noise floor

    /// What the comparison sees when nothing changed must sit well inside the thresholds.
    @Test func noiseFloorIsInsideTheThresholds() throws {
        var floors: [(String, ColorDifference.Summary)] = []
        for name in ["chart24.neutral", "gradient.default-look", "gradient.grain", "iphone12pro-proraw.graded"] {
            let c = try RegressionCase.named(name)
            let scene = try c.scene()
            let comparison = try #require(
                VisualRegression.compare(
                    VisualRegression.render(scene, c.adjustments), VisualRegression.render(scene, c.adjustments), structure: true))
            floors.append(("\(name) rendered twice", comparison.summary))
            #expect(c.thresholds.accepts(comparison.summary, structuralSimilarity: comparison.structuralSimilarity))
        }

        let gradient = try RegressionCase.named("gradient.default-look")
        let renderer = VisualRegression.renderer
        let lazy = Negative(image: try gradient.scene(), contract: .sceneReferred)
        let materialized = try renderer.materialize(lazy)
        let lazyRender = RegressionImage(rendering: try renderer.render(lazy, gradient.adjustments))
        let materializedRender = RegressionImage(rendering: try renderer.render(materialized, gradient.adjustments))
        floors.append(
            ("gradient.default-look lazy vs materialized", try #require(VisualRegression.compare(lazyRender, materializedRender)).summary))

        let chart = try renderer.render(Negative(image: SceneFixtures.chart24(), contract: .sceneReferred), .neutral)
        let quantized = RegressionImage(rendering: chart)
        let floats = Self.encodedFloats(chart).map { simd_clamp($0, .zero, .one) }
        let quantization = zip(floats, quantized.encoded).map(ColorDifference.deltaE2000(displayP3:_:))
        floors.append(("chart24.neutral float vs 16-bit", ColorDifference.Summary(quantization)))

        for (label, s) in floors {
            print(String(format: "noise floor %@: mean %.6f p95 %.6f max %.6f", label, s.mean, s.p95, s.max))
            #expect(VisualRegression.thresholds.accepts(s), "\(label): \(s)")
        }
    }

    /// Display P3 encoded floats (clipped to the 16-bit range by the caller), top row first. Not
    /// `Fixtures.encodedFloats`: this reads back through the same half-float context as the 16-bit
    /// path, so the difference measured is quantisation alone.
    private static func encodedFloats(_ image: CIImage) -> [SIMD3<Double>] {
        let (w, h) = (Int(image.extent.width), Int(image.extent.height))
        var f = [Float](repeating: 0, count: w * h * 4)
        RegressionImage.context.render(
            image, toBitmap: &f, rowBytes: w * 16, bounds: image.extent, format: .RGBAf, colorSpace: Renderer.outputSpace)
        return (0..<w * h).map { SIMD3(Double(f[$0 * 4]), Double(f[$0 * 4 + 1]), Double(f[$0 * 4 + 2])) }
    }

    // MARK: File formats

    @Test func goldenPNGRoundTripsExactly() throws {
        let codes: [UInt16] = [0, 1, 255, 256, 32768, 65534, 65535]
        let pixels = codes.indices.map { i in SIMD3(codes[i], codes[(i + 2) % codes.count], codes[(i + 5) % codes.count]) }
        let image = RegressionImage(width: codes.count, height: 1, pixels: pixels)
        #expect(try RegressionImage(pngData: image.pngData()) == image)
        let tall = RegressionImage(width: 2, height: 3, pixels: Array(pixels.prefix(6)))
        #expect(try RegressionImage(pngData: tall.pngData()) == tall)
    }

    @Test func sceneTIFFRoundTripsHalfFloatsExactly() throws {
        let scene = Fixtures.image(width: 24, height: 5, space: SceneFixtures.linear) { x, y in
            let level = -0.5 + 12 * Float(x) / 23
            return SIMD3(level, level * 0.5 - Float(y) * 0.1, 11.5 - level)
        }
        let half = SceneFile.halfImage(rendering: scene)
        let readBack = try SceneFile.halfImage(tiffData: SceneFile.tiffData(half))
        #expect(readBack == half)
        let linear = Fixtures.linear(SceneFile.image(readBack))
        #expect(linear.map { $0.max() }.max() == 12)
        #expect((linear.map { $0.min() }.min() ?? 0) < 0)
        #expect(SceneFile.halfImage(rendering: SceneFile.image(readBack)) == half, "colour matching changed the stored values")
    }

    // MARK: Frozen real scenes

    /// Develops the CC0 sources into `Scenes/` (run when the RAW develop changes on purpose):
    /// `EMULSION_REGENERATE_SCENES=<folder with the sources> swift test --filter regeneratesFrozenScenes`.
    @Test(.enabled(if: VisualRegression.sceneSourceDirectory != nil))
    func regeneratesFrozenScenes() throws {
        let source = try #require(VisualRegression.sceneSourceDirectory)
        let output = VisualRegression.sourceScenes
        let renderer = VisualRegression.renderer
        for scene in RealScene.allCases {
            let raw = try Data(contentsOf: source.appending(path: scene.sourceName))
            let developed = try renderer.developer.develop(raw, maxDimension: RealScene.developDimension)
            let frozen = renderer.resized(developed, longestEdge: RealScene.frozenLongEdge)
            let half = SceneFile.halfImage(rendering: frozen.image)
            let file = try SceneFile.tiffData(half)
            #expect(try SceneFile.halfImage(tiffData: file) == half)
            try file.write(to: output.appending(path: "\(scene.rawValue).tiff"))
            print("\(scene.sourceName): \(raw.count) bytes, SHA-256 \(Self.sha256(raw))")
            print("  → \(scene.rawValue).tiff: \(half.width)×\(half.height), \(file.count) bytes, SHA-256 \(Self.sha256(file))")
        }
    }

    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // MARK: Local tier

    /// Every DNG under `EMULSION_REFERENCE_SAMPLES`, developed and rendered with the default look,
    /// against goldens kept in `<folder>/emulsion-goldens/` (never in git). Covers the RAW develop.
    @Test(.enabled(if: VisualRegression.referenceSamplesDirectory != nil))
    func localSamplesMatchLocalGoldens() throws {
        let folder = try #require(VisualRegression.referenceSamplesDirectory).standardizedFileURL
        let goldens = folder.appending(path: "emulsion-goldens")
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        let samples = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "dng" && !$0.path.hasPrefix(goldens.path) }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
        try #require(!samples.isEmpty, "no DNG files under \(folder.path)")
        let renderer = VisualRegression.renderer
        let items = samples.map { url in
            VisualRegression.Item(name: String(url.path.dropFirst(folder.path.count + 1)), thresholds: VisualRegression.photoThresholds) {
                let negative = try renderer.developer.develop(Data(contentsOf: url), maxDimension: Self.localDevelopDimension)
                return RegressionImage(rendering: try renderer.render(negative, RegressionCase.defaultLook))
            }
        }
        try VisualRegression.run(
            "local samples", items, store: .local(goldens), reportDirectory: VisualRegression.reportDirectory.appending(path: "local"),
            regenerate: "add EMULSION_UPDATE_GOLDENS=1 (local goldens stay outside git).")
    }

    private static let localDevelopDimension: CGFloat = 512
}
