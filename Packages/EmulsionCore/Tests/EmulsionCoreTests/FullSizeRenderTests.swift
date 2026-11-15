import CoreGraphics
import CoreImage
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionCore

/// Real-file render repeatability (MOV-147); can't run on CI (docs/CONSTANTS.md).
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct FullSizeRenderTests {
    /// Before the fix, 4 repeats caught the intermittent corruption in one of two runs.
    static let repeats = 8

    @Test func fullSizeRendersAreRepeatable() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        for url in urls {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let renderer = try Renderer()
            let first = try renderer.developer.develop(data, maxDimension: nil)
            let anchor = first.exposureAnchorStops
            let other = try Renderer()
            _ = try other.export(other.render(other.developer.develop(data, exposureAnchorStops: anchor), .neutral), format: .jpeg)

            let export = try renderer.export(renderer.render(first, .neutral), format: .jpeg)
            let negative = SceneFile.halfImage(rendering: try renderer.materialize(first).image)
            let display = try Self.pixels(renderer.cgImage(renderer.render(first, .neutral)))
            for run in 1..<Self.repeats {
                let developed = try renderer.developer.develop(data, maxDimension: nil, exposureAnchorStops: anchor)
                #expect(try renderer.export(renderer.render(developed, .neutral), format: .jpeg) == export, "\(name): export \(run)")
                #expect(SceneFile.halfImage(rendering: try renderer.materialize(developed).image) == negative, "\(name): negative \(run)")
                #expect(try Self.pixels(renderer.cgImage(renderer.render(developed, .neutral))) == display, "\(name): cgImage \(run)")
            }
        }
    }

    static func pixels(_ image: CGImage) -> Data? { image.dataProvider?.data as Data? }
}

@Test func everyRenderCachesIntermediates() {
    #expect(Renderer.contextOptions[.cacheIntermediates] as? Bool == true)
}

@Test(arguments: RenderProcess.allCases) func viewfinderRendersOnlyCameraFrames(_ process: RenderProcess) throws {
    let renderer = EmulsionTestCase.sharedRenderer
    var look = Adjustments.neutral
    look.process = process
    let frame = SceneFixtures.flat(0.18, width: 16, height: 16)
    #expect(throws: Never.self) { try renderer.viewfinderImage(renderer.developer.viewfinderNegative(from: frame), look) }
    let dng = RAWDevelopChart.dng(.linearRGB, chart: RAWDevelopTests.chart, baselineStops: 0)
    let raw = try renderer.developer.develop(dng)
    #expect(throws: EmulsionError.renderFailed) { try renderer.viewfinderImage(raw, look) }
}

/// Apple's noise-reduction kernel for `contrastAmount` 0, which binds a wrong intermediate into whole render tiles
/// (MOV-147, docs/ENGINE.md). The synthetic Bayer DNG reaches it at contrast 0; any other contrast avoids it.
@Test func developNeverRunsAppleContrastZeroKernel() throws {
    let dng = RAWDevelopChart.dng(.bayerRGGB, chart: RAWDevelopTests.chart)
    let raw = try #require(CIRAWFilter(imageData: dng, identifierHint: Developer.dngTypeIdentifier))
    Developer.bypassAppleRendering(raw)
    let graph = try #require(raw.outputImage).debugDescription
    #expect(graph.contains("nr_"), "the decode graph no longer names Apple's noise-reduction kernels; update this check")
    #expect(!graph.contains("nr_expandAndSharpenThroughGradientMaskGather"))
}

/// Every RAW develop is one owned buffer, so no render can read Apple's lazy decode (MOV-147).
@Test(arguments: SyntheticDNG.Mosaic.allCases, [nil, 64] as [CGFloat?])
func everyRAWDevelopIsAnOwnedBuffer(_ mosaic: SyntheticDNG.Mosaic, maxDimension: CGFloat?) throws {
    let developer = EmulsionTestCase.sharedRenderer.developer
    let dng = RAWDevelopChart.dng(mosaic, chart: RAWDevelopTests.chart)
    #expect(try developer.develop(dng, maxDimension: maxDimension).image.pixelBuffer != nil)
    let decoder = try #require(developer.rawDecoder(dng, maxDimension: maxDimension))
    #expect(try decoder.negative().image.pixelBuffer != nil)
    #expect(try decoder.negative(whiteBalance: CameraWhiteBalance(temperature: 3200, tint: 0)).image.pixelBuffer != nil)
}
