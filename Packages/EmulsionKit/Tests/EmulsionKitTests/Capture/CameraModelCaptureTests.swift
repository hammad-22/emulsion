import CoreGraphics
import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct CameraModelCaptureTests {
    @Test func switchingLensUpdatesCapabilities() async {
        let library = TestLibrary()
        let model = library.camera(MockCameraSource())
        await model.start()

        await model.select(.ultraWide)

        #expect(model.capabilities?.lens == .ultraWide)
        #expect(model.capabilities?.supportsFullResolution == false)
    }

    @Test func focusForwardsThePointAndShowsTheReticleBriefly() async throws {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = library.camera(source)
        model.focusIndicatorDuration = .milliseconds(20)
        await model.start()
        let point = CGPoint(x: 0.25, y: 0.75)

        await model.focus(at: point)

        #expect(model.focusPoint == point)
        #expect(await source.lastFocusPoint == point)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.focusPoint == nil)
    }

    @Test func captureAddsOneUneditedPhotoToTheLibrary() async throws {
        let library = TestLibrary()
        let existing = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let model = library.camera(MockCameraSource())
        await model.start()

        library.settings.resolution = .full
        await model.capture()

        let captured = try #require(model.lastCapture)
        #expect(library.store.photos.map(\.id) == [captured.id, existing.id], "newest first")
        #expect(FileManager.default.fileExists(atPath: library.store.url(for: captured).path(percentEncoded: false)))
        #expect(captured.adjustments == .defaults(for: captured.id))
        #expect(model.captureCount == 1)
        #expect(!model.isCapturing)
        #expect(model.error == nil)
    }

    @Test func captureStartsWithTheRecipeAsItsEdit() async throws {
        let library = TestLibrary()
        let recipe = try TestLooks.curated(1)
        library.settings.recipe = recipe
        let model = library.camera()
        await model.start()

        await model.capture()

        let captured = try #require(model.lastCapture)
        // As applying the look in the editor would: the recipe, with the photo's own grain seed.
        let expected = recipe.applying(to: .defaults(for: captured.id))
        #expect(captured.adjustments == expected)
        #expect(library.reopened().photo(captured.id)?.adjustments == expected, "saved in the index")
    }

    @Test func captureKeepsTheRecipeAtShutterPress() async throws {
        let library = TestLibrary()
        let shutter = ShutterHold()
        library.settings.recipe = try TestLooks.curated(1)
        let model = library.camera(MockCameraSource(captureGate: shutter.gate))
        await model.start()

        let capture = Task { await model.capture() }
        await shutter.waitUntilCaptureStarts()
        model.recipe = try TestLooks.curated(2)
        shutter.release()
        await capture.value

        let captured = try #require(model.lastCapture)
        let first = try TestLooks.curated(1)
        #expect(captured.adjustments == first.applying(to: .defaults(for: captured.id)))
    }

    @Test func lensSwitchIsIgnoredWhileCapturing() async throws {
        let library = TestLibrary()
        let shutter = ShutterHold()
        let model = library.camera(MockCameraSource(captureGate: shutter.gate))
        await model.start()

        let capture = Task { await model.capture() }
        await shutter.waitUntilCaptureStarts()
        await model.select(.telephoto)
        #expect(model.capabilities?.lens == .wide)
        shutter.release()
        await capture.value

        #expect(model.lastCapture != nil)
        #expect(model.error == nil)
    }

    @Test func failedCaptureReportsAndAddsNothing() async {
        let library = TestLibrary()
        let model = library.camera(MockCameraSource(captureError: .captureFailed))
        await model.start()

        await model.capture()

        #expect(model.error == .captureFailed)
        #expect(library.store.photos.isEmpty)
        #expect(model.lastCapture == nil)
    }

    @Test func fullResolutionFallsBackWhereTheLensLacksIt() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = library.camera(source)
        await model.start()
        await model.select(.ultraWide)

        library.settings.resolution = .full
        await model.capture()

        #expect(await source.lastCaptureResolution == .standard)
        await model.select(.wide)
        library.settings.resolution = .full
        await model.capture()
        #expect(await source.lastCaptureResolution == .full)
    }

    @Test func nothingIsCapturedWhileStopped() async {
        let library = TestLibrary()
        let model = library.camera(MockCameraSource())

        await model.capture()

        #expect(library.store.photos.isEmpty)
        #expect(model.captureCount == 0)
    }
}
