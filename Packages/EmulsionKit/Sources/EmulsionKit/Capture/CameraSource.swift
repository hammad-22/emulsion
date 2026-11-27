import CoreGraphics
import QuartzCore

/// `AVCameraSource` on device, `MockCameraSource` elsewhere. See Packages/EmulsionKit/NOTES.md, "CameraSource".
public protocol CameraSource: Sendable {
    func frames() -> AsyncStream<CameraFrame>
    func events() -> AsyncStream<CameraEvent>
    func start(lens: CameraLens) async throws(CameraError) -> CameraCapabilities
    func stop() async
    func select(_ lens: CameraLens, zoomFactor: Double) async throws(CameraError) -> CameraCapabilities
    func changeExposure(_ change: CameraExposure.Change) async throws(CameraError) -> CameraCapabilities
    /// `framePoint` is 0…1 of the upright frame as displayed, top-left origin.
    func focusAndExpose(at framePoint: CGPoint) async
    func capture(_ resolution: AppSettings.Resolution) async throws(CameraError) -> CapturedPhoto
    func attachViewfinder(_ layer: ViewfinderLayer) async
}

/// `@unchecked Sendable` is safe: only the rotation coordinator uses the layer, weakly, on main.
public struct ViewfinderLayer: @unchecked Sendable {
    public weak var layer: CALayer?

    public init(_ layer: CALayer) {
        self.layer = layer
    }
}
