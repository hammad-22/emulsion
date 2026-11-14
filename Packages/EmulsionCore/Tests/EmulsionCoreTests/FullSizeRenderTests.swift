import CoreImage
import CryptoKit
import Foundation
import Testing

@testable import EmulsionCore

/// Full-size renders of real DNGs from EMULSION_RAW_SAMPLES (never checked in) are repeatable
/// (MOV-147). Apple's RAW decode at full size with `contrastAmount` 0, rendered through a context
/// that doesn't cache intermediates, returns corrupted tiles that vary from render to render. Only
/// real ProRAW triggers it: synthetic DNGs (12 and 48 MP, linear and Bayer) render the same every
/// time, so this can't run on CI.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct FullSizeRenderTests {
    /// The corruption is intermittent: before the fix, 4 repeats caught it on two 48 MP iPhone 15
    /// Pro Max files in one of two runs. A pass makes it unlikely, it doesn't prove it absent.
    static let repeats = 8

    @Test func fullSizeExportsAndMaterializedNegativesAreRepeatable() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        for url in urls {
            let data = try Data(contentsOf: url)
            let renderer = try Renderer()
            let anchor = try renderer.developer.develop(data, maxDimension: nil).exposureAnchorStops
            // The corruption also followed another context decoding the same file first.
            let other = try Renderer()
            _ = try other.export(other.render(other.developer.develop(data, exposureAnchorStops: anchor), .neutral), format: .jpeg)

            var exports: Set<String> = []
            var negatives: Set<String> = []
            for _ in 0..<Self.repeats {
                let developed = try renderer.developer.develop(data, maxDimension: nil, exposureAnchorStops: anchor)
                exports.insert(Self.digest(try renderer.export(renderer.render(developed, .neutral), format: .jpeg)))
                negatives.insert(Self.digest(try renderer.materialize(developed)))
            }
            #expect(exports.count == 1, "\(url.lastPathComponent): \(exports.count) different exports in \(Self.repeats)")
            #expect(negatives.count == 1, "\(url.lastPathComponent): \(negatives.count) different negatives in \(Self.repeats)")
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Reads a materialized negative back exactly (half float in, half float out). Its graph is a
    /// pixel buffer, with no RAW decode left in it.
    static let readback = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])

    /// The materialized negative's half-float pixels.
    static func digest(_ negative: Negative) -> String {
        let bounds = negative.image.extent
        let rowBytes = Int(bounds.width) * 8
        var pixels = Data(count: rowBytes * Int(bounds.height))
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            readback.render(
                negative.image, toBitmap: base, rowBytes: rowBytes, bounds: bounds, format: .RGBAh, colorSpace: Renderer.workingSpace)
        }
        return digest(pixels)
    }
}
