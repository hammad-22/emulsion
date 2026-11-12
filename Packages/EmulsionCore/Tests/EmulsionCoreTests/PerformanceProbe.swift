import CoreImage
import EmulsionFixtures
import ImageIO
import XCTest
import simd

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

    /// RAW develop without the exposure anchor (before), measuring it (after) and given the
    /// anchor an earlier develop reported (known anchor, MOV-134), developed and materialized,
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
            let measured = try r.developer.develop(data, maxDimension: ExposureAnchor.thumbnailLongEdge).exposureAnchorStops
            let variants: [(name: String, anchor: ExposureAnchor.Choice)] = [
                ("before", .none), ("after", .measured), ("known anchor", .known(stops: measured)),
            ]
            for edge in [CGFloat(1024), 1600, nil] {
                for variant in variants {
                    var anchor = 0.0
                    let times = try Self.milliseconds(runs: 4) {
                        let negative = try r.developer.develop(data, maxDimension: edge, anchor: variant.anchor)
                        _ = try r.materialize(negative)
                        anchor = negative.exposureAnchorStops
                    }
                    let median = times.dropFirst().sorted()[1]
                    print(
                        "| \(url.lastPathComponent) | \(Int(size.width))×\(Int(size.height)) | \(edge.map { "\(Int($0))" } ?? "full")"
                            + " | \(variant.name) | \(String(format: "%.0f", median))"
                            + " | \(String(format: "%.0f", times[0])) | \(String(format: "%+.3f", anchor)) |")
                }
            }
        }
    }

    /// RAW white balance (MOV-10), for the first DNG of each camera make and native size in
    /// EMULSION_RAW_SAMPLES. Opt-in: EMULSION_PERF=1. Three tables: the develop at 1024 px with and
    /// without a white balance; the output render alone after the anchor, to see whether a new
    /// white balance throws away the decode the anchor left (and whether setting it before or after
    /// the preview scale matters); and one warm filter re-rendered at a new temperature, the cost
    /// of an interactive white-balance path that keeps the filter alive.
    func testRAWWhiteBalanceTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run")
        try XCTSkipUnless(RAWDevelopSupport.samplesFolders != nil, "set EMULSION_RAW_SAMPLES to run")
        let r = try Renderer()
        let context = CIContext(options: [
            .workingColorSpace: Renderer.workingSpace, .workingFormat: CIFormat.RGBAh, .outputColorSpace: Renderer.outputSpace,
            .cacheIntermediates: false,
        ])
        var seen = Set<String>()
        var files: [(name: String, data: Data, size: CGSize)] = []
        for url in try RAWDevelopSupport.sampleURLs() {
            let data = try Data(contentsOf: url)
            let size = try RAWDevelopSupport.filter(data).nativeSize
            let hint = [kCGImageSourceTypeIdentifierHint: Developer.dngTypeIdentifier] as CFDictionary
            let properties = CGImageSourceCreateWithData(data as CFData, hint).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) }
            let tiff = (properties as? [CFString: Any])?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let make = tiff?[kCGImagePropertyTIFFMake] as? String ?? "?"
            if seen.insert("\(make) \(size)").inserted { files.append((url.lastPathComponent, data, size)) }
        }
        let edge: CGFloat = 1024
        func median(_ times: [Double]) -> String { String(format: "%.0f", times.dropFirst().sorted()[times.count / 2 - 1]) }
        func ms(_ value: Double) -> String { String(format: "%.0f", value) }

        print("\n| File | Native size | Develop, as shot (median / first ms) | Develop, 3200 K (median / first ms) |")
        print("| --- | --- | ---: | ---: |")
        for (name, data, size) in files {
            let asShot = try Self.milliseconds(runs: 5) { _ = try r.materialize(try r.developer.develop(data, maxDimension: edge)) }
            let balanced = try Self.milliseconds(runs: 5) {
                _ = try r.materialize(
                    try r.developer.develop(data, maxDimension: edge, whiteBalance: CameraWhiteBalance(temperature: 3200, tint: 0)))
            }
            print(
                "| \(name) | \(Int(size.width))×\(Int(size.height)) | \(median(asShot)) / \(ms(asShot[0]))"
                    + " | \(median(balanced)) / \(ms(balanced[0])) |")
        }

        enum Order: String, CaseIterable {
            case asShot = "as shot"
            case afterScale = "3200 K after scale"
            case beforeScale = "3200 K before scale"
        }
        /// The develop's steps on a fresh filter; only the output render is timed.
        func outputRender(_ data: Data, _ order: Order) throws -> (ms: Double, pixels: [SIMD4<Float>]) {
            let raw = try RAWDevelopSupport.filter(data)
            Developer.bypassAppleRendering(raw)
            let anchors = raw.isLocalToneMapSupported
            if anchors {
                Developer.applyPreviewScale(raw, maxDimension: ExposureAnchor.thumbnailLongEdge, allowsDraftMode: false)
                _ = ExposureAnchor.stops(of: raw, context: context)
            }
            let whiteBalance = CameraWhiteBalance(temperature: 3200, tint: 0)
            if order == .beforeScale { Developer.apply(whiteBalance, to: raw) }
            Developer.applyPreviewScale(raw, maxDimension: edge, allowsDraftMode: !anchors)
            if order == .afterScale { Developer.apply(whiteBalance, to: raw) }
            let start = ContinuousClock.now
            let pixels = RAWDevelopProbe.rgba(try XCTUnwrap(raw.outputImage), context: context)
            return ((ContinuousClock.now - start).milliseconds, pixels)
        }
        print(
            "\n| File | Output render after the anchor: \(Order.allCases.map(\.rawValue).joined(separator: " | ")) (median ms) | Max diff, before vs after scale |"
        )
        print("| --- | ---: | ---: | ---: | ---: |")
        for (name, data, _) in files {
            var cells: [String] = []
            var last: [Order: [SIMD4<Float>]] = [:]
            for order in Order.allCases {
                var times: [Double] = []
                for _ in 0..<5 {
                    let (time, pixels) = try outputRender(data, order)
                    times.append(time)
                    last[order] = pixels
                }
                cells.append(median(times))
            }
            let before = try XCTUnwrap(last[.beforeScale])
            let after = try XCTUnwrap(last[.afterScale])
            let difference = before.count == after.count ? zip(before, after).map { abs($0 - $1).max() }.max() ?? 0 : .infinity
            print("| \(name) | \(cells.joined(separator: " | ")) | \(Double(difference).fourDigits) |")
        }

        print("\n| File | Long edge | First render ms | New temperature, re-render (median / max ms of 8) |")
        print("| --- | ---: | ---: | ---: |")
        for (name, data, _) in files {
            for warmEdge in [CGFloat(1024), 1600] {
                let raw = try RAWDevelopSupport.filter(data)
                Developer.bypassAppleRendering(raw)
                Developer.applyPreviewScale(raw, maxDimension: warmEdge, allowsDraftMode: !raw.isLocalToneMapSupported)
                let first = try Self.milliseconds(runs: 1) { _ = RAWDevelopProbe.rgba(try XCTUnwrap(raw.outputImage), context: context) }
                var times: [Double] = []
                for kelvin in stride(from: 3000.0, through: 6500, by: 500) {
                    times += try Self.milliseconds(runs: 1) {
                        Developer.apply(CameraWhiteBalance(temperature: kelvin, tint: Double(raw.neutralTint)), to: raw)
                        _ = RAWDevelopProbe.rgba(try XCTUnwrap(raw.outputImage), context: context)
                    }
                }
                let sorted = times.sorted()
                print(
                    "| \(name) | \(Int(warmEdge)) | \(ms(first[0])) | \(String(format: "%.0f", sorted[sorted.count / 2])) / \(ms(sorted.last ?? .nan)) |"
                )
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
