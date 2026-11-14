import CoreGraphics
import EmulsionCore
import Testing

@testable import EmulsionKit

@MainActor
struct ViewfinderRenderTests {
    @Test func viewfinderImageIsFittedWithTheFramesAspect() async throws {
        let library = TestLibrary()
        let frame = try TestFrames.grey(width: 640, height: 480)

        let image = try await library.renderService.viewfinderImage(frame, Adjustments(), maxDimension: 320)

        #expect(image.width == 320)
        #expect(image.height == 240)
    }

    /// A fractional fitted size is floored, as `Renderer.resized` does, so there's no partly
    /// covered (translucent) edge row or column.
    @Test func viewfinderFitHasNoPartialEdgePixels() async throws {
        let library = TestLibrary()
        let frame = try TestFrames.grey(width: 1920, height: 1440)

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

    /// A frame stuck behind the actor never finishes, so the time limit cancels the test, which
    /// frees the actor and fails the expectation instead of hanging.
    @Test(.timeLimit(.minutes(5)))
    func viewfinderRendersWhileTheServiceIsBusy() async throws {
        let library = TestLibrary()
        let frame = try TestFrames.grey(width: 640, height: 480)
        try await library.renderService.prepareViewfinder()
        let hold = ActorHold()
        defer { hold.release() }
        Task { await library.renderService.occupy(until: hold) }
        await hold.waitUntilOccupied()

        _ = try await withTaskCancellationHandler {
            try await library.renderService.viewfinderImage(frame, .neutral, maxDimension: 320)
        } onCancel: {
            hold.release()
        }

        #expect(hold.isOccupying, "the frame waited for the actor to be free")
    }

    @Test func viewfinderImageIsTurnedUpright() async throws {
        let library = TestLibrary()
        let frame = CameraFrame(pixelBuffer: try TestFrames.grey(width: 640, height: 480).pixelBuffer, rotationAngle: 90)

        let image = try await library.renderService.viewfinderImage(frame, Adjustments(), maxDimension: 320)

        #expect(image.width == 240)
        #expect(image.height == 320)
    }

    /// Kit adds nothing to Core's viewfinder develop: the same pixels through Core's reference
    /// path give the same picture (the estimate's accuracy is Core's `ViewfinderEstimateTests`).
    @Test(arguments: [Adjustments(), .neutral])
    func viewfinderMatchesCoresViewfinderDevelop(look: Adjustments) async throws {
        let library = TestLibrary()
        let renderer = try #require(TestLibrary.renderer)
        let frame = try TestFrames.sample()

        let viewfinder = try await library.renderService.viewfinderImage(frame, look, maxDimension: 1800)
        let reference = try renderer.cgImage(renderer.render(renderer.developer.viewfinderNegative(from: frame.uprightImage), look))

        #expect(viewfinder.width == reference.width && viewfinder.height == reference.height)
        let difference = TestPixels.difference(viewfinder, reference)
        #expect(difference.max <= 1, "max \(difference.max), mean \(difference.mean)")
    }

    @Test func recipesLookDifferentAndTheSameRecipeRepeats() async throws {
        let library = TestLibrary()
        let frame = try TestFrames.sample()
        func render(_ recipe: Recipe) async throws -> CGImage {
            try await library.renderService.viewfinderImage(frame, recipe.adjustments, maxDimension: 600)
        }

        let standard = try await render(try TestLooks.curated(0))
        let warm = try await render(try TestLooks.curated(1))
        let again = try await render(try TestLooks.curated(0))

        #expect(TestPixels.difference(standard, warm).mean > 2, "a recipe shows in the viewfinder")
        #expect(TestPixels.difference(standard, again).max == 0, "same recipe and seed, same picture")
    }
}
