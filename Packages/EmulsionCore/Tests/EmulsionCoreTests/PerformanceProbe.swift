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
            var times = [Double]()
            for _ in 0..<5 {
                let t = Date()
                let cg = try r.cgImage(try r.render(neg, adj))
                _ = cg.dataProvider?.data
                times.append(Date().timeIntervalSince(t) * 1000)
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
        var files: [(url: URL, size: CGSize)] = []
        for url in try RAWDevelopSupport.sampleURLs() {
            guard let raw = CIRAWFilter(imageURL: url) else { continue }
            if seenSizes.insert("\(raw.nativeSize)").inserted { files.append((url, raw.nativeSize)) }
        }
        print("| File | Native size | Long edge | Variant | Median ms | First ms | Anchor |")
        print("| --- | --- | ---: | --- | ---: | ---: | ---: |")
        for (url, size) in files {
            let data = try Data(contentsOf: url)
            for edge in [CGFloat(1024), 1600, nil] {
                for variant in RAWVariant.allCases where edge != nil || !variant.isDraftOnly {
                    var times = [Double]()
                    var anchor = 0.0
                    for _ in 0..<4 {
                        let start = ContinuousClock.now
                        let negative = try variant.develop(data, maxDimension: edge, with: r)
                        _ = try r.materialize(negative)
                        times.append((ContinuousClock.now - start).milliseconds)
                        anchor = negative.exposureAnchorStops
                    }
                    let median = times.dropFirst().sorted()[1]
                    print(
                        "| \(url.lastPathComponent) | \(Int(size.width))×\(Int(size.height)) | \(edge.map { "\(Int($0))" } ?? "full")"
                            + " | \(variant.rawValue) | \(String(format: "%.0f", median)) | \(String(format: "%.0f", times[0]))"
                            + " | \(String(format: "%+.3f", anchor)) |")
                }
            }
        }
    }

    /// Develop orders compared for the draft-mode decision.
    private enum RAWVariant: String, CaseIterable {
        case before = "before: no anchor, draft on"
        case beforeDraftOff = "no anchor, draft off"
        case after = "after: anchor, draft off"
        case afterDraftOn = "anchor, then draft on for the output"

        /// Draft mode only differs below full size.
        var isDraftOnly: Bool { self == .beforeDraftOff || self == .afterDraftOn }

        func develop(_ data: Data, maxDimension: CGFloat?, with r: Renderer) throws -> Negative {
            switch self {
            case .before: return try r.developer.develop(data, maxDimension: maxDimension, anchorsExposure: false)
            case .after: return try r.developer.develop(data, maxDimension: maxDimension)
            case .beforeDraftOff, .afterDraftOn:
                let raw = try XCTUnwrap(CIRAWFilter(imageData: data, identifierHint: Developer.dngTypeIdentifier))
                Developer.bypassAppleRendering(raw)
                let anchor = self == .afterDraftOn && raw.isLocalToneMapSupported ? ExposureAnchor.stops(of: raw, context: r.context) : 0
                Developer.applyPreviewScale(raw, maxDimension: maxDimension, allowsDraftMode: self == .afterDraftOn)
                let output = try XCTUnwrap(raw.outputImage).applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: anchor])
                return Negative(image: Developer.normalized(output), contract: .sceneReferred, exposureAnchorStops: anchor)
            }
        }
    }
}
