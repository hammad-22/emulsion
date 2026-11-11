import CoreGraphics
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct CameraModelTests {
    @Test func startRunsWithTheSourcesCapabilities() async {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(), store: library.store)

        await model.start()

        #expect(model.status == .running)
        #expect(model.capabilities?.lens == .wide)
        #expect(model.capabilities?.lenses.map(\.lens) == [.ultraWide, .wide, .telephoto])
        #expect(model.capabilities?.rawFormat == .proRAW)
    }

    @Test func unauthorizedCameraShowsUnauthorized() async {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(authorized: false), store: library.store)

        await model.start()

        #expect(model.status == .unauthorized)
        #expect(model.capabilities == nil)
        #expect(model.error == nil, "the screen explains it; no alert as well")
    }

    @Test func startAndStopAreIdempotent() async {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(), store: library.store)

        await model.stop()
        #expect(model.status == .idle)
        await model.start()
        await model.start()
        #expect(model.status == .running)
        await model.stop()
        await model.stop()
        #expect(model.status == .idle)
        await model.start()
        #expect(model.status == .running)
    }

    @Test func switchingLensUpdatesCapabilities() async {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(), store: library.store)
        await model.start()

        await model.select(.ultraWide)

        #expect(model.capabilities?.lens == .ultraWide)
        #expect(model.capabilities?.supportsFullResolution == false)
    }

    @Test func focusForwardsThePointAndShowsTheReticleBriefly() async throws {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = CameraModel(source: source, store: library.store)
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
        let model = CameraModel(source: MockCameraSource(), store: library.store)
        await model.start()

        await model.capture(resolution: .full)

        let captured = try #require(model.lastCapture)
        #expect(library.store.photos.map(\.id) == [captured.id, existing.id], "newest first")
        #expect(FileManager.default.fileExists(atPath: library.store.url(for: captured).path(percentEncoded: false)))
        #expect(captured.adjustments == .defaults(for: captured.id))
        #expect(model.captureCount == 1)
        #expect(!model.isCapturing)
        #expect(model.error == nil)
    }

    @Test func failedCaptureReportsAndAddsNothing() async {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(captureError: .captureFailed), store: library.store)
        await model.start()

        await model.capture(resolution: .standard)

        #expect(model.error == .captureFailed)
        #expect(library.store.photos.isEmpty)
        #expect(model.lastCapture == nil)
    }

    @Test func fullResolutionFallsBackWhereTheLensLacksIt() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = CameraModel(source: source, store: library.store)
        await model.start()
        await model.select(.ultraWide)

        await model.capture(resolution: .full)

        #expect(await source.lastCaptureResolution == .standard)
        await model.select(.wide)
        await model.capture(resolution: .full)
        #expect(await source.lastCaptureResolution == .full)
    }

    @Test func nothingIsCapturedWhileStopped() async {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(), store: library.store)

        await model.capture(resolution: .standard)

        #expect(library.store.photos.isEmpty)
        #expect(model.captureCount == 0)
    }
}
