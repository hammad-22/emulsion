import CoreGraphics
import QuartzCore

/// The device's back cameras (`AVCameraSource`) or, in the Simulator and tests, `MockCameraSource`.
public protocol CameraSource: Sendable {
    /// Newest only; each call starts a new stream and finishes the previous one.
    func frames() -> AsyncStream<CameraFrame>
    /// Every event, in order; each call starts a new stream and finishes the previous one.
    func events() -> AsyncStream<CameraEvent>
    /// Falls back to the wide lens if the device lacks `lens`; asks for camera access if undecided.
    func start(lens: CameraLens) async throws(CameraError) -> CameraCapabilities
    func stop() async
    func select(_ lens: CameraLens) async throws(CameraError) -> CameraCapabilities
    /// `framePoint` is 0…1 of the upright frame, top-left origin. Focus returns to continuous
    /// when the scene changes.
    func focusAndExpose(at framePoint: CGPoint) async
    func capture(_ resolution: AppSettings.Resolution) async throws(CameraError) -> CapturedPhoto
    /// So frames can be turned upright for the interface orientation the layer is shown in.
    func attachViewfinder(_ layer: ViewfinderLayer) async
}

/// `@unchecked Sendable` is safe: the camera never touches the layer itself; it only hands
/// it to `AVCaptureDevice.RotationCoordinator`, which keeps it weakly and reports on the
/// main queue (AVCaptureDevice.h), as Apple's AVCam sample does from its capture actor.
public struct ViewfinderLayer: @unchecked Sendable {
    public weak var layer: CALayer?

    public init(_ layer: CALayer) {
        self.layer = layer
    }
}
