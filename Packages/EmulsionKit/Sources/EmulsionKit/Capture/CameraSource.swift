import CoreGraphics
import QuartzCore

/// A camera the app can drive: the device's back cameras (`AVCameraSource`) or, in the
/// Simulator and tests, `MockCameraSource`.
public protocol CameraSource: Sendable {
    /// Viewfinder frames, newest only: a slow consumer skips frames instead of queueing
    /// them. Each call starts a new stream and finishes the previous one.
    func frames() -> AsyncStream<CameraFrame>
    /// What happens to the camera on its own: interruptions, unrecoverable errors, system
    /// pressure. Every event, in order. Each call starts a new stream and finishes the previous one.
    func events() -> AsyncStream<CameraEvent>
    /// Starts the camera on `lens` (or the wide lens if the device lacks it), asking for
    /// camera access first if the user hasn't decided yet.
    func start(lens: CameraLens) async throws(CameraError) -> CameraCapabilities
    func stop() async
    func select(_ lens: CameraLens) async throws(CameraError) -> CameraCapabilities
    /// Focuses and exposes once at a point of the upright frame as displayed: 0…1, top-left
    /// origin. The camera returns to continuous focus when the scene changes.
    func focusAndExpose(at framePoint: CGPoint) async
    func capture(_ resolution: AppSettings.Resolution) async throws(CameraError) -> CapturedPhoto
    /// The layer the viewfinder is drawn in, so frames can be turned upright for the
    /// interface orientation it's displayed in.
    func attachViewfinder(_ layer: ViewfinderLayer) async
}

/// The layer showing the viewfinder.
///
/// `@unchecked Sendable` is safe: the camera never touches the layer itself; it only hands
/// it to `AVCaptureDevice.RotationCoordinator`, which keeps it weakly and reports on the
/// main queue (AVCaptureDevice.h), as Apple's AVCam sample does from its capture actor.
public struct ViewfinderLayer: @unchecked Sendable {
    public weak var layer: CALayer?

    public init(_ layer: CALayer) {
        self.layer = layer
    }
}
