import CoreGraphics
import CoreImage
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionCore

/// Real-file full-size renders checked tile by tile against an independent decode (MOV-147); can't run on CI
/// (docs/CONSTANTS.md). Each render must also repeat bit for bit.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct FullSizeRenderTests {
    static let repeats = 4
    /// Core Image's tiles are 256 px or larger; corrupted ones measured 15–134 codes off.
    static let tileSize = 256
    /// Measured worst clean tile 1.3 codes (mean |Δ| per channel) against the reference's other kernel path.
    static let tileTolerance = 3.0
    static let look: Adjustments = {
        var look = Adjustments()
        look.halation = 1
        look.seed = 7
        return look
    }()

    @Test func fullSizeRendersMatchAnIndependentDecode() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        for url in urls {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let renderer = try Renderer()
            let anchor = try #require(renderer.developer.rawDecoder(data, maxDimension: nil, anchor: .measured)).exposureAnchorStops
            let reference = try Self.pixels(renderer.cgImage(renderer.render(Self.referenceNegative(data, anchor: anchor), Self.look)))
            var exports: [Data] = []
            for run in 0..<Self.repeats {
                let developed = try renderer.developer.develop(data, exposureAnchorStops: anchor)
                exports.append(try renderer.export(renderer.render(developed, Self.look), format: .jpeg))
                let rendered = try Self.pixels(renderer.cgImage(renderer.render(developed, Self.look)))
                // A later graph that reads the develop with no caching at all: a lazy decode corrupts there.
                let uncached = try Self.pixels(Self.renderUncached(renderer.render(Self.uncachedRead(developed), Self.look)))
                for (label, pixels) in [("render", rendered), ("uncached read", uncached)] {
                    let bad = Self.badTiles(pixels, reference)
                    #expect(bad.isEmpty, "\(name) \(label) \(run): \(bad.count) tiles off, first \(bad.first.map { "\($0)" } ?? "")")
                }
            }
            #expect(Set(exports).count == 1, "\(name): exports differ between runs")
        }
    }

    /// Apple's contrast-0 path (the develop's is `Developer.nearZeroContrast`), rendered alone into a buffer
    /// through a caching context, where it measured clean.
    static func referenceNegative(_ data: Data, anchor: Double) throws -> Negative {
        let raw = try RAWDevelopSupport.filter(data)
        Developer.bypassAppleRendering(raw)
        if raw.isContrastSupported { raw.contrastAmount = 0 }
        return try RAWDecoder(raw, exposureAnchorStops: anchor, context: RAWDevelopSupport.rendererLikeContext).negative()
    }

    static func uncachedRead(_ negative: Negative) -> Negative {
        Negative(image: negative.image.insertingIntermediate(cache: false), contract: negative.contract)
    }

    static let uncachedContext = CIContext(options: Renderer.contextOptions.merging([.cacheIntermediates: false]) { $1 })

    static func renderUncached(_ image: CIImage) throws -> CGImage {
        try #require(uncachedContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: Renderer.outputSpace))
    }

    struct Pixels {
        let width: Int
        let height: Int
        let rowBytes: Int
        let bytes: Data
    }

    static func pixels(_ image: CGImage) throws -> Pixels {
        let bytes = try #require(image.dataProvider?.data as Data?)
        return Pixels(width: image.width, height: image.height, rowBytes: image.bytesPerRow, bytes: bytes)
    }

    /// Origins of tiles whose mean |Δ| per colour channel is over `tileTolerance` codes.
    static func badTiles(_ a: Pixels, _ b: Pixels) -> [CGPoint] {
        guard a.width == b.width, a.height == b.height else { return [.zero] }
        let origins = stride(from: 0, to: a.height, by: tileSize).flatMap { y in
            stride(from: 0, to: a.width, by: tileSize).map { x in (x: x, y: y) }
        }
        return origins.filter { meanTileDifference(a, b, x: $0.x, y: $0.y) > tileTolerance }.map { CGPoint(x: $0.x, y: $0.y) }
    }

    private static func meanTileDifference(_ a: Pixels, _ b: Pixels, x tileX: Int, y tileY: Int) -> Double {
        var sum = 0
        var count = 0
        a.bytes.withUnsafeBytes { pa in
            b.bytes.withUnsafeBytes { pb in
                for y in tileY..<min(tileY + tileSize, a.height) {
                    for x in tileX..<min(tileX + tileSize, a.width) {
                        for channel in 0..<3 {
                            sum += abs(Int(pa[y * a.rowBytes + x * 4 + channel]) - Int(pb[y * b.rowBytes + x * 4 + channel]))
                        }
                        count += 3
                    }
                }
            }
        }
        return Double(sum) / Double(count)
    }
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

/// At contrast exactly 0 Apple's decode corrupts whole render tiles (MOV-147, docs/ENGINE.md).
@Test func developNeverSetsContrastToZero() throws {
    let raw = try RAWDevelopSupport.filter(RAWDevelopChart.dng(.bayerRGGB, chart: RAWDevelopTests.chart))
    try #require(raw.isContrastSupported, "the synthetic Bayer DNG no longer supports contrast; use a file that does")
    Developer.bypassAppleRendering(raw)
    #expect(raw.contrastAmount == Developer.nearZeroContrast)
    #expect(Developer.nearZeroContrast > 0)
}

/// Every RAW develop is one owned buffer, so no render can read Apple's lazy decode (MOV-147).
@Test(arguments: SyntheticDNG.Mosaic.allCases, [nil, 64] as [CGFloat?])
func everyRAWDevelopIsAnOwnedBuffer(_ mosaic: SyntheticDNG.Mosaic, maxDimension: CGFloat?) throws {
    let developer = EmulsionTestCase.sharedRenderer.developer
    let dng = RAWDevelopChart.dng(mosaic, chart: RAWDevelopTests.chart)
    func isHalfFloatBuffer(_ negative: Negative) -> Bool {
        negative.image.pixelBuffer.map(CVPixelBufferGetPixelFormatType) == kCVPixelFormatType_64RGBAHalf
    }
    #expect(isHalfFloatBuffer(try developer.develop(dng, maxDimension: maxDimension)))
    let decoder = try #require(developer.rawDecoder(dng, maxDimension: maxDimension))
    #expect(isHalfFloatBuffer(try decoder.negative()))
    #expect(isHalfFloatBuffer(try decoder.negative(whiteBalance: CameraWhiteBalance(temperature: 3200, tint: 0))))
}

/// The develop is Apple's decode rendered once into a half-float buffer: within half-float rounding of the decode read
/// through a context like the renderer's (Core Image's half-float working format already moves Bayer decodes more).
@Test(arguments: SyntheticDNG.Mosaic.allCases, [nil, CameraWhiteBalance(temperature: 3200, tint: 10)])
func developIsTheDecodeInHalfFloat(_ mosaic: SyntheticDNG.Mosaic, whiteBalance: CameraWhiteBalance?) throws {
    let dng = RAWDevelopChart.dng(mosaic, chart: RAWDevelopTests.chart, baselineStops: 1)
    let developed = try EmulsionTestCase.sharedRenderer.developer.develop(dng, whiteBalance: whiteBalance).image
    let decoded = try RAWDevelopSupport.decode(dng, whiteBalance: whiteBalance).image
    let worst = RAWDevelopSupport.worstRelativeDifference(
        RAWDevelopSupport.linearThroughRendererContext(developed), RAWDevelopSupport.linearThroughRendererContext(decoded),
        floor: RAWDevelopSupport.halfFloatFloor)
    #expect(worst < RAWDevelopSupport.halfFloatTolerance, "worst relative difference \(worst)")
}
