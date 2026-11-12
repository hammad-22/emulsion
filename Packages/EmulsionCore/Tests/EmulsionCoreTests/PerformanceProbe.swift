import CoreImage
import EmulsionFixtures
import XCTest

@testable import EmulsionCore

/// Mac timing of the full render at preview, 12 MP and 48 MP. Opt-in: EMULSION_PERF=1.
final class PerformanceProbe: XCTestCase {
    func testTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run")
        let r = try Renderer()
        var a = Adjustments()
        a.grain = 0.5
        a.halation = 0.5
        a.shadows = 0.3
        a.highlights = 0.3
        a.seed = 2
        for (w, h) in [(1600, 1200), (4032, 3024), (8064, 6048)] {
            /// A smooth 64×48 tile scaled up to the timed size.
            func upscaled(_ space: CGColorSpace, _ color: (Int, Int) -> SIMD3<Float>) -> CIImage {
                Fixtures.image(width: 64, height: 48, space: space, color)
                    .samplingLinear().transformed(by: CGAffineTransform(scaleX: CGFloat(w) / 64, y: CGFloat(h) / 48))
                    .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            }
            let scene = upscaled(SceneFixtures.linear) { x, y in SIMD3(Float(x) / 16, Float(y) / 24, 0.18) }
            try time(r, Negative(image: scene, contract: .sceneReferred), "", full: a, w, h)
            // A JPEG/HEIC: developed and materialized once (not timed), then rendered.
            let picture = upscaled(DisplayFixtures.displayP3) { x, y in SIMD3(Float(x) / 63, Float(y) / 47, 0.5) }
            try time(r, try r.materialize(try r.developer.sceneFromDisplay(picture)), "display-referred ", full: a, w, h)
            // A viewfinder frame: estimated every frame, by the preview inverse or the per-pixel solve.
            try time(r, r.developer.viewfinderNegative(from: picture), "viewfinder ", full: a, w, h)
            let solved = try r.developer.sceneFromDisplay(picture).image
            try time(r, Negative(image: solved, contract: .previewEstimate), "viewfinder via per-pixel solve ", full: a, w, h)
        }
    }

    private func time(_ r: Renderer, _ neg: Negative, _ kind: String, full a: Adjustments, _ w: Int, _ h: Int) throws {
        for (label, adj) in [("look only", Adjustments.neutral), ("full", a)] {
            let times = try Self.milliseconds(runs: 5) {
                let cg = try r.cgImage(try r.render(neg, adj))
                _ = cg.dataProvider?.data
            }
            print(String(format: "%dx%d %@%@: median %.1f ms (first %.1f)", w, h, kind, label, times.dropFirst().sorted()[2], times[0]))
        }
    }

    /// RAW develop with and without the exposure anchor (MOV-134), developed and materialized,
    /// for the first DNG of each native size in EMULSION_RAW_SAMPLES. Opt-in: EMULSION_PERF=1.
    func testRAWDevelopTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run")
        try XCTSkipUnless(RAWDevelopSupport.samplesFolders != nil, "set EMULSION_RAW_SAMPLES to run")
        let r = try Renderer()
        var seenSizes = Set<String>()
        var files: [(url: URL, data: Data, size: CGSize)] = []
        for url in try RAWDevelopSupport.sampleURLs() {
            let data = try Data(contentsOf: url)
            let size = try RAWDevelopSupport.filter(data).nativeSize
            if seenSizes.insert("\(size)").inserted { files.append((url, data, size)) }
        }
        print("| File | Native size | Long edge | Variant | Median ms | First ms | Anchor |")
        print("| --- | --- | ---: | --- | ---: | ---: | ---: |")
        for (url, data, size) in files {
            for edge in [CGFloat(1024), 1600, nil] {
                for anchorsExposure in [false, true] {
                    var anchor = 0.0
                    let times = try Self.milliseconds(runs: 4) {
                        let negative = try r.developer.develop(data, maxDimension: edge, anchorsExposure: anchorsExposure)
                        _ = try r.materialize(negative)
                        anchor = negative.exposureAnchorStops
                    }
                    let median = times.dropFirst().sorted()[1]
                    print(
                        "| \(url.lastPathComponent) | \(Int(size.width))×\(Int(size.height)) | \(edge.map { "\(Int($0))" } ?? "full")"
                            + " | \(anchorsExposure ? "after" : "before") | \(String(format: "%.0f", median))"
                            + " | \(String(format: "%.0f", times[0])) | \(String(format: "%+.3f", anchor)) |")
                }
            }
        }
    }

    /// Wall-clock milliseconds of each of `runs` calls of `body`.
    private static func milliseconds(runs: Int, _ body: () throws -> Void) rethrows -> [Double] {
        try (0..<runs).map { _ in
            let start = ContinuousClock.now
            try body()
            return (ContinuousClock.now - start).milliseconds
        }
    }
}
