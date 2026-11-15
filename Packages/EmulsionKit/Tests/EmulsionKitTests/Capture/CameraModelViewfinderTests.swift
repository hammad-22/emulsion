import CoreGraphics
import EmulsionCore
import Testing

@testable import EmulsionKit

@MainActor
struct CameraModelViewfinderTests {
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
        #expect(TestPixels.redOverBlue(after) > TestPixels.redOverBlue(before) + 9, "warmer after the change")
    }
}
