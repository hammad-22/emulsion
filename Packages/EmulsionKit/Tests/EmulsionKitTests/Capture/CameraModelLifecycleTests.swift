import CoreGraphics
import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct CameraModelLifecycleTests {
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

    @Test func interruptionPausesTheCameraUntilItEnds() async {
        let library = TestLibrary()
        let source = MockCameraSource()
        let model = library.camera(source)
        await model.start()

        await source.emit(.interrupted(.inUseByAnotherApp))
        await CameraTestSupport.settle { model.status != .running }

        #expect(model.status == .interrupted(.inUseByAnotherApp))
        await model.capture()
        await model.select(.telephoto)
        #expect(model.captureCount == 0)
        #expect(model.capabilities?.lens == .wide)
        #expect(!model.acceptsInput)

        await source.emit(.interruptionEnded)
        await CameraTestSupport.settle { model.status == .running }

        #expect(model.status == .running)
        await model.capture()
        #expect(model.lastCapture != nil)
    }

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

    @Test func interruptionArrivingAfterStopIsIgnored() async {
        let library = TestLibrary()
        let model = library.camera()
        await model.start()
        await model.stop()

        model.handle(.interrupted(.inUseByAnotherApp))
        await model.start()

        #expect(model.status == .running)
    }

    /// So a later recovery can't restart the camera behind the app.
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
        await CameraTestSupport.settle { model.pressure == .critical }

        #expect(model.pressure == .critical)
        #expect(model.status == .running, "the camera keeps running, slower")
    }

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
}
