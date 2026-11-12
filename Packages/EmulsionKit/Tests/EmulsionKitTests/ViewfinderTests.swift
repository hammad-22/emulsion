import CoreImage
import CoreVideo
import EmulsionCore
import Foundation
import ImageIO
import Synchronization
import Testing

@testable import EmulsionKit

@MainActor
struct ViewfinderTests {
    @Test func mockDeliversUprightBGRAFrames() async throws {
        let source = MockCameraSource()
        let frames = source.frames()
        _ = try await source.start(lens: .wide)
        defer { Task { await source.stop() } }

        var iterator = frames.makeAsyncIterator()
        let frame = try #require(await iterator.next())

        #expect(CVPixelBufferGetPixelFormatType(frame.pixelBuffer) == kCVPixelFormatType_32BGRA)
        #expect(frame.rotationAngle == 0, "already upright")
        #expect(CVPixelBufferGetHeight(frame.pixelBuffer) > CVPixelBufferGetWidth(frame.pixelBuffer), "portrait, like a phone held upright")
    }

    @Test func viewfinderImageIsFittedWithTheFramesAspect() async throws {
        let library = TestLibrary()
        let frame = try Self.frame(width: 640, height: 480)

        let image = try await library.renderService.viewfinderImage(frame, Adjustments(), maxDimension: 320)

        #expect(image.width == 320)
        #expect(image.height == 240)
    }

    /// A fractional fitted size is floored, as `Renderer.resized` does, so there's no partly
    /// covered (translucent) edge row or column.
    @Test func viewfinderFitHasNoPartialEdgePixels() async throws {
        let library = TestLibrary()
        let frame = try Self.frame(width: 1920, height: 1440)

        let image = try await library.renderService.viewfinderImage(frame, .neutral, maxDimension: 1179)

        #expect(image.width == 1179)
        #expect(image.height == 884, "1440 × 1179/1920 = 884.25, floored")
        let pixels = TestPixels.rgba(image)
        let (width, height) = (image.width, image.height)
        var edges: [Int] = []
        for x in 0..<width { edges += [x, (height - 1) * width + x] }
        for y in 0..<height { edges += [y * width, y * width + width - 1] }
        #expect(edges.allSatisfy { pixels[$0 * 4 + 3] == 255 }, "edge pixels are opaque")
    }

    /// The stand-in camera's frames keep their exact size all through the pan.
    @Test func mockFramesStayTheFrameSizeThroughThePan() async throws {
        let source = MockCameraSource()
        _ = try await source.start(lens: .wide)
        await source.stop()

        for step in 0..<64 {
            let frame = try #require(await source.frame(at: Double(step) * 0.137))
            #expect(CVPixelBufferGetWidth(frame.pixelBuffer) == Int(MockCameraSource.frameSize.width), "step \(step)")
            #expect(CVPixelBufferGetHeight(frame.pixelBuffer) == Int(MockCameraSource.frameSize.height), "step \(step)")
        }
    }

    /// Viewfinder frames don't queue behind library renders on the service's actor.
    @Test func viewfinderRendersWhileTheServiceIsBusy() async throws {
        let library = TestLibrary()
        let frame = try Self.frame(width: 640, height: 480)
        try await library.renderService.prepareViewfinder()
        let released = DispatchSemaphore(value: 0)

        // Holds the actor until the viewfinder frame is done, or gives up after a timeout far
        // longer than a frame takes: only a viewfinder stuck behind the actor reaches it.
        let busy = Task.detached { await library.renderService.hold(until: released, timeout: .seconds(10)) }
        await library.renderService.waitUntilHeld()
        _ = try await library.renderService.viewfinderImage(frame, .neutral, maxDimension: 320)
        released.signal()

        #expect(await busy.value, "the frame finished while the actor was still busy")
    }

    @Test func viewfinderImageIsTurnedUpright() async throws {
        let library = TestLibrary()
        let frame = CameraFrame(pixelBuffer: try Self.frame(width: 640, height: 480).pixelBuffer, rotationAngle: 90)

        let image = try await library.renderService.viewfinderImage(frame, Adjustments(), maxDimension: 320)

        #expect(image.width == 240)
        #expect(image.height == 320)
    }

    @Test func modelStreamsRenderedFramesAndTimesThem() async throws {
        let library = TestLibrary()
        let model = library.camera()
        model.recordsViewfinderTiming = true
        let images = model.viewfinderImages(maxDimension: 256)
        await model.start()

        var iterator = images.makeAsyncIterator()
        let first = try #require(await iterator.next())
        _ = await iterator.next()
        await model.stop()

        #expect(max(first.width, first.height) == 256)
        #expect(model.viewfinderTiming.meanRenderMilliseconds > 0)
        #expect(model.viewfinderTiming.framesPerSecond > 0)
    }

    /// Kit adds nothing to Core's viewfinder develop: the same pixels through Core's reference
    /// path give the same picture (the estimate's accuracy is Core's `ViewfinderEstimateTests`).
    @Test(arguments: [Adjustments(), .neutral])
    func viewfinderMatchesCoresViewfinderDevelop(look: Adjustments) async throws {
        let library = TestLibrary()
        let renderer = try #require(TestLibrary.renderer)
        let frame = try Self.sampleFrame()

        let viewfinder = try await library.renderService.viewfinderImage(frame, look, maxDimension: 1800)
        let reference = try renderer.cgImage(renderer.render(renderer.developer.viewfinderNegative(from: frame.uprightImage), look))

        #expect(viewfinder.width == reference.width && viewfinder.height == reference.height)
        let difference = TestPixels.difference(viewfinder, reference)
        #expect(difference.max <= 1, "max \(difference.max), mean \(difference.mean)")
    }

    @Test func recipesLookDifferentAndTheSameRecipeRepeats() async throws {
        let library = TestLibrary()
        let frame = try Self.sampleFrame()
        func render(_ recipe: Recipe) async throws -> CGImage {
            try await library.renderService.viewfinderImage(frame, recipe.adjustments, maxDimension: 600)
        }

        let standard = try await render(try TestLooks.curated(0))
        let warm = try await render(try TestLooks.curated(1))
        let again = try await render(try TestLooks.curated(0))

        #expect(TestPixels.difference(standard, warm).mean > 2, "a recipe shows in the viewfinder")
        #expect(TestPixels.difference(standard, again).max == 0, "same recipe and seed, same picture")
    }

    @Test func viewfinderGrainChangesEveryFrame() throws {
        let library = TestLibrary()
        library.settings.recipe = try TestLooks.curated(1)
        let model = library.camera()
        let seeds = (0..<1025).map { model.viewfinderLook(frameNumber: $0).seed }

        #expect(Set(seeds[..<1024]).count == 1024)
        #expect(seeds.allSatisfy { $0 >= 0 && $0 <= 1023 && $0 == $0.rounded() })
        var withoutSeed = model.viewfinderLook(frameNumber: 7)
        withoutSeed.seed = 0
        #expect(withoutSeed == model.recipe.adjustments, "everything else is the recipe")
    }

    /// Changing the recipe reaches the running stream on a later frame, without restarting it.
    @Test func recipeChangeReachesTheRunningViewfinder() async throws {
        let library = TestLibrary()
        library.settings.recipe = try TestLooks.curated(2)
        let model = library.camera()
        let images = model.viewfinderImages(maxDimension: 128)
        await model.start()
        defer { Task { await model.stop() } }
        var iterator = images.makeAsyncIterator()

        let before = try #require(await iterator.next())
        model.recipe = try TestLooks.curated(1)
        var after = before
        for _ in 0..<3 { after = try #require(await iterator.next()) }

        // Measured: red over blue rose by 16.7 codes, Quiet Color to Warm Light.
        #expect(Self.redOverBlue(after) > Self.redOverBlue(before) + 9, "warmer after the change")
    }

    /// A frame filled with a mid grey, tagged sRGB like the mock camera's.
    static func frame(width: Int, height: Int) throws -> CameraFrame {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CameraFrame.sRGB,
                bitmapInfo: CameraFrame.bgra))
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage().flatMap(CameraFrame.init(drawing:)))
    }

    /// The first bundled sample at its own size (1800 × 1200), as an sRGB BGRA camera frame.
    static func sampleFrame() throws -> CameraFrame {
        let url = try #require(PhotoStore.sampleURLs.first)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap(CameraFrame.init(drawing:)))
    }

    /// Mean red minus mean blue, in 8-bit codes.
    private static func redOverBlue(_ image: CGImage) -> Double {
        let bytes = TestPixels.rgba(image)
        let pixels = bytes.count / 4
        let red = stride(from: 0, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
        let blue = stride(from: 2, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
        return Double(red - blue) / Double(pixels)
    }
}

/// Mean viewfinder render time (film look included) at typical iPhone viewfinder sizes, with
/// the default look and with grain and halation off. Opt-in: EMULSION_PERF=1. Mac numbers only.
@MainActor
struct ViewfinderPerformanceProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run"))
    func viewfinderRenderTime() async throws {
        let library = TestLibrary()
        let frame = try ViewfinderTests.frame(width: 4032 / 2, height: 3024 / 2)
        let frames = 120
        for (name, look) in [("default look", Adjustments()), ("no grain or halation", Adjustments.neutral)] {
            for longEdge: CGFloat in [1280, 1920] {
                _ = try await library.renderService.viewfinderImage(frame, look, maxDimension: longEdge)  // warm up
                let elapsed = try await ContinuousClock().measure {
                    for _ in 0..<frames { _ = try await library.renderService.viewfinderImage(frame, look, maxDimension: longEdge) }
                }
                let mean = String(format: "%.2f", elapsed / .milliseconds(1) / Double(frames))
                print("viewfinderImage, \(name): \(mean) ms mean over \(frames) frames at \(Int(longEdge)) px")
            }
        }
    }
}

extension RenderService {
    /// Occupies the actor, as a long library render would, until `released` is signalled.
    /// Returns false if it timed out instead.
    func hold(until released: DispatchSemaphore, timeout: Duration) -> Bool {
        isHeld.withLock { $0 = true }
        let seconds = timeout / .seconds(1)
        return released.wait(timeout: .now() + seconds) == .success
    }

    /// Waits (off the actor) until `hold` has the actor.
    nonisolated func waitUntilHeld() async {
        while !isHeld.withLock({ $0 }) { await Task.yield() }
    }
}

private let isHeld = Mutex(false)
