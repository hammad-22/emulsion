import CoreGraphics
import CoreImage
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionCore

/// Full-size exports, materialized negatives and display renders of real DNGs from
/// EMULSION_RAW_SAMPLES (never checked in) repeat bit for bit (MOV-147, docs/ENGINE.md). Only
/// real ProRAW triggers the corruption, so this can't run on CI.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct FullSizeRenderTests {
    /// The corruption is intermittent: before the fix, 4 repeats caught it on two 48 MP iPhone 15
    /// Pro Max files in one of two runs. A pass makes it unlikely, it doesn't prove it absent.
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
            // The corruption also followed another context decoding the same file first.
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

/// Every render but viewfinder frames, and the developer's, goes through a context that caches
/// intermediates: without that, a full-size RAW decode comes back with corrupted tiles (MOV-147).
/// Real ProRAW is needed to trigger it, so on CI this checks the setting itself.
@Test func everyRenderCachesIntermediates() {
    #expect(Renderer.contextOptions[.cacheIntermediates] as? Bool == true)
}

/// The viewfinder's context skips caching, so it takes only a camera frame's preview estimate:
/// a RAW develop, or anything else, is refused (MOV-147), in either render process (the digicam
/// process renders a viewfinder frame as a preview, so its export-only JPEG step never runs there).
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
