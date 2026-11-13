import CoreGraphics
import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct CameraModelTests {
    @Test func startRunsWithTheSourcesCapabilities() async {
        let library = TestLibrary()
        let model = library.camera(MockCameraSource())

        await model.start()

        #expect(model.status == .running)
        #expect(model.capabilities?.lens == .wide)
        #expect(model.capabilities?.lenses.map(\.lens) == [.ultraWide, .wide, .telephoto])
        #expect(model.capabilities?.rawFormat == .proRAW)
    }

    @Test(arguments: [(CameraError.notAuthorized, CameraModel.Status.unauthorized), (.restricted, .restricted)])
    func deniedAccessShowsWhy(error: CameraError, status: CameraModel.Status) async {
        let library = TestLibrary()
        let model = library.camera(MockCameraSource(failingStartWith: error))

        await model.start()

        #expect(model.status == status)
        #expect(model.capabilities == nil)
        #expect(model.error == nil, "the screen explains it; no alert as well")
    }

    /// Another app takes the camera: the shutter and lenses stop working until it's back, and
    /// the camera resumes on its own.
    @Test func interruptionPausesTheCameraUntilItEnds() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = library.camera(source)
        await model.start()

        await source.emit(.interrupted(.inUseByAnotherApp))
        await Self.settle { model.status != .running }

        #expect(model.status == .interrupted(.inUseByAnotherApp))
        await model.capture()
        await model.select(.telephoto)
        #expect(model.captureCount == 0)
        #expect(model.capabilities?.lens == .wide)
        #expect(!model.acceptsInput)

        await source.emit(.interruptionEnded)
        await Self.settle { model.status == .running }

        #expect(model.status == .running)
        await model.capture()
        #expect(model.lastCapture != nil)
    }

    /// Leaving the screen forgets an interruption: the session reports it again on the next start
    /// if the camera is still taken.
    @Test func stoppingForgetsAnInterruption() async {
        let library = TestLibrary()
        let model = library.camera()
        await model.start()
        model.handle(.interrupted(.multipleForegroundApps))

        await model.stop()
        #expect(model.status == .idle)
        await model.start()

        #expect(model.status == .running)
    }

    /// An interruption reported before the camera stopped, but handled after, doesn't leave the
    /// next session looking paused.
    @Test func interruptionArrivingAfterStopIsIgnored() async {
        let library = TestLibrary()
        let model = library.camera()
        await model.start()
        await model.stop()

        model.handle(.interrupted(.inUseByAnotherApp))
        await model.start()

        #expect(model.status == .running)
    }

    /// A camera that failed while running is still stopped on leaving the screen, so a later
    /// recovery can't restart it behind the app.
    @Test func stoppingAFailedCameraStopsTheSource() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = library.camera(source)
        await model.start()
        model.handle(.failed)

        await model.stop()

        #expect(model.status == .idle)
        #expect(await !source.isRunning)
    }

    /// An unrecoverable session error shows the camera as unavailable; starting again retries.
    @Test func sessionFailureIsUnavailableUntilRetried() async {
        let library = TestLibrary()
        let model = library.camera()
        model.handle(.failed)
        #expect(model.status == .idle, "a stopped camera can't fail")
        await model.start()
        model.handle(.interrupted(.other))

        model.handle(.failed)

        #expect(model.status == .unavailable)
        await model.start()
        #expect(model.status == .running, "the failure cleared the interruption")
    }

    @Test func pressureIsReported() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = library.camera(source)
        await model.start()

        await source.emit(.pressure(.critical))
        await Self.settle { model.pressure == .critical }

        #expect(model.pressure == .critical)
        #expect(model.status == .running, "the camera keeps running, slower")
    }

    /// Stopping (the app going to the background) stops the source, and nothing keeps a
    /// discarded camera alive.
    @Test func stoppedCameraHoldsNothing() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        weak var released: CameraModel?
        do {
            let model = library.camera(source)
            await model.start()
            #expect(await source.isRunning)
            await model.stop()
            released = model
        }

        #expect(await !source.isRunning)
        #expect(released == nil)
    }

    /// Lets the model's event task run until `condition` holds; a bounded number of turns, not
    /// a wall-clock wait (MOV-138).
    private static func settle(until condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
    }

    @Test func startAndStopAreIdempotent() async {
        let library = TestLibrary()
        let model = library.camera(MockCameraSource())

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

    /// The photo gets the recipe shown when the shutter was pressed, even if the recipe changes
    /// while the camera is still capturing.
    @Test func captureKeepsTheRecipeAtShutterPress() async throws {
        let library = TestLibrary()
        let gate = Self.captureGate()
        library.settings.recipe = try TestLooks.curated(1)
        let model = library.camera(MockCameraSource(captureGate: gate.gate))
        await model.start()

        let capture = Task { await model.capture() }
        await gate.started()
        model.recipe = try TestLooks.curated(2)
        gate.release()
        await capture.value

        let captured = try #require(model.lastCapture)
        let first = try TestLooks.curated(1)
        #expect(captured.adjustments == first.applying(to: .defaults(for: captured.id)))
    }

    /// A lens switch can't land mid-capture: it's ignored, and the capture still succeeds.
    @Test func lensSwitchIsIgnoredWhileCapturing() async throws {
        let library = TestLibrary()
        let gate = Self.captureGate()
        let model = library.camera(MockCameraSource(captureGate: gate.gate))
        await model.start()

        let capture = Task { await model.capture() }
        await gate.started()
        await model.select(.telephoto)
        #expect(model.capabilities?.lens == .wide)
        gate.release()
        await capture.value

        #expect(model.lastCapture != nil)
        #expect(model.error == nil)
    }

    /// A capture gate and the calls a test makes on it.
    private static func captureGate() -> (gate: MockCameraSource.CaptureGate, started: () async -> Void, release: () -> Void) {
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let gate = MockCameraSource.CaptureGate(started: startedContinuation, release: release)
        return (gate, { for await _ in started { break } }, { releaseContinuation.yield() })
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
