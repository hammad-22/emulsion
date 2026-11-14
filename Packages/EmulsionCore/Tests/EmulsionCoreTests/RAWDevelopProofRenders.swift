import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Before/after PNGs through the neutral film look for the PRs (MOV-79, MOV-134). EMULSION_PROOF_DIR
/// names the output folder. Real files: only the CC0 samples (names ending in `_CC0.dng`) are rendered.
@Suite(.enabled(if: TestEnvironment.proofDirectory.isSet), .serialized)
struct RAWDevelopProofRenders {
    /// Small enough to keep each PNG to a few hundred KB.
    static let longEdge: CGFloat = 640
    static let wedgeBaselineStops = 2.0

    static func write(_ negative: Negative, to url: URL) throws {
        try EmulsionTestCase.writePNG(RAWDevelopTests.renderer.render(negative, .neutral), to: url)
    }

    static func cc0Samples() throws -> [URL] {
        try RAWDevelopSupport.sampleURLs().filter { $0.lastPathComponent.lowercased().hasSuffix("_cc0.dng") }
    }

    static func outputFolder() throws -> URL {
        let folder = URL(fileURLWithPath: try #require(TestEnvironment.proofDirectory.value), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func writesBeforeAfterRenders() throws {
        let folder = try Self.outputFolder()
        let developer = RAWDevelopTests.developer

        let chart = RAWDevelopChart.chart(cell: 96)
        let wedge = RAWDevelopChart.dng(.bayerRGGB, chart: chart, baselineStops: Self.wedgeBaselineStops)
        let wedgeFilter = try #require(CIRAWFilter(imageData: wedge, identifierHint: nil))
        try Self.write(RAWDevelopSupport.preMOV79Negative(wedgeFilter), to: folder.appendingPathComponent("wedge-before.png"))
        try Self.write(developer.develop(wedge), to: folder.appendingPathComponent("wedge-after.png"))

        for url in try Self.cc0Samples() {
            let name = url.deletingPathExtension().lastPathComponent
            let raw = try #require(CIRAWFilter(imageURL: url))
            try Self.write(
                RAWDevelopSupport.preMOV79Negative(raw, maxDimension: Self.longEdge),
                to: folder.appendingPathComponent("\(name)-before.png"))
            try Self.write(
                developer.develop(Data(contentsOf: url), maxDimension: Self.longEdge),
                to: folder.appendingPathComponent("\(name)-after.png"))
        }
    }

    /// MOV-134: before is the develop without the exposure anchor, after is with it.
    @Test func writesExposureAnchorRenders() throws {
        let folder = try Self.outputFolder()
        let developer = RAWDevelopTests.developer
        for url in try Self.cc0Samples() {
            let name = url.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: url)
            try Self.write(
                developer.develop(data, maxDimension: Self.longEdge, anchor: .none),
                to: folder.appendingPathComponent("\(name)-anchor-before.png"))
            let anchored = try developer.develop(data, maxDimension: Self.longEdge)
            print("\(name): exposure anchor \(String(format: "%+.3f", anchored.exposureAnchorStops)) stops")
            try Self.write(anchored, to: folder.appendingPathComponent("\(name)-anchor-after.png"))
        }
    }

    /// MOV-10: the tungsten chart tagged as daylight, as shot and at 2856 K, with the correctly
    /// tagged file as the reference; the CC0 real files as shot, cooler and warmer.
    @Test func writesWhiteBalanceRenders() throws {
        let folder = try Self.outputFolder()
        let developer = RAWDevelopTests.developer
        let chart = PatchChart(CameraWhiteBalanceTests.scene, cell: 80)
        let tungsten = CameraWhiteBalanceTests.tungsten
        let wrong = RAWDevelopChart.dng(.bayerRGGB, chart: chart, light: tungsten, taggedLight: CameraWhiteBalanceTests.d65)
        let right = RAWDevelopChart.dng(.bayerRGGB, chart: chart, light: tungsten, taggedLight: tungsten)
        let corrected = CameraWhiteBalance(temperature: CameraWhiteBalanceTests.tungstenKelvin, tint: 0)
        try Self.write(developer.develop(wrong), to: folder.appendingPathComponent("wb-wrong-tag-before.png"))
        try Self.write(developer.develop(wrong, whiteBalance: corrected), to: folder.appendingPathComponent("wb-wrong-tag-after.png"))
        try Self.write(developer.develop(right), to: folder.appendingPathComponent("wb-right-tag-reference.png"))

        for url in try Self.cc0Samples() {
            let name = url.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: url)
            let asShot = try #require(try developer.develop(data, maxDimension: Self.longEdge).asShotWhiteBalance)
            for (label, factor) in [("as-shot", 1.0), ("cooler", 0.75), ("warmer", 1.35)] {
                let whiteBalance = CameraWhiteBalance(temperature: asShot.temperature * factor, tint: asShot.tint)
                print("\(name) \(label): \(whiteBalance.temperature) K, tint \(whiteBalance.tint)")
                try Self.write(
                    developer.develop(data, maxDimension: Self.longEdge, whiteBalance: factor == 1 ? nil : whiteBalance),
                    to: folder.appendingPathComponent("\(name)-wb-\(label).png"))
            }
        }
    }
}
