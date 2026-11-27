import CoreGraphics
import Testing

@testable import EmulsionKit

@MainActor
struct CameraExposureTests {
    @Test func exposureDefaultsToAutoAndPreservesManualSettingsWhenFocusing() async throws {
        let library = TestLibrary()
        let model = library.camera()
        await model.start()
        let automatic = try #require(model.capabilities?.exposure)
        #expect(!automatic.isManual)
        #expect(automatic.apertureStops.isEmpty)

        await model.changeExposure(.shutter(seconds: 1.0 / 250))
        await model.changeExposure(.iso(400))
        await model.focus(at: CGPoint(x: 0.25, y: 0.75))

        let manual = try #require(model.capabilities?.exposure)
        #expect(manual.isManual)
        #expect(manual.shutterSeconds == 1.0 / 250)
        #expect(manual.iso == 400)
        #expect(manual.aperture == automatic.aperture)

        await model.changeExposure(.automatic)
        #expect(model.capabilities?.exposure == automatic)
    }

    @Test func switchingLensesRestoresAutomaticExposure() async throws {
        let library = TestLibrary()
        let model = library.camera()
        await model.start()
        await model.changeExposure(.iso(400))
        #expect(model.capabilities?.exposure?.isManual == true)

        await model.select(.telephoto)

        let exposure = try #require(model.capabilities?.exposure)
        #expect(!exposure.isManual)
        #expect(exposure.aperture == 2.8)
    }

    @Test func rejectsAnOutOfRangeOrFixedApertureSetting() async throws {
        let library = TestLibrary()
        let model = library.camera()
        await model.start()
        let automatic = try #require(model.capabilities?.exposure)

        await model.changeExposure(.shutter(seconds: 5))
        await model.changeExposure(.iso(12_800))
        await model.changeExposure(.aperture(4))

        #expect(model.capabilities?.exposure == automatic)
    }

    @Test func doesNotApplyChangesWhileShutterIsInFlight() async throws {
        let library = TestLibrary()
        let shutter = ShutterHold()
        let model = library.camera(MockCameraSource(captureGate: shutter.gate))
        await model.start()

        let capture = Task { await model.capture() }
        await shutter.waitUntilCaptureStarts()
        await model.changeExposure(.iso(400))
        #expect(model.capabilities?.exposure?.isManual == false)
        shutter.release()
        await capture.value

        #expect(model.lastCapture != nil)
        #expect(model.error == nil)
    }

    @Test func suppliesAtLeastOneChoiceInAnUnusuallyNarrowRange() {
        #expect(CameraExposure.shutterStops(in: 0.019...0.020) == [0.019])
        #expect(CameraExposure.isoStops(in: 225...230) == [225])
    }
}
