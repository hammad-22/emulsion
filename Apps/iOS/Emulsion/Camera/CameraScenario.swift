import EmulsionKit
import Foundation

#if DEBUG && targetEnvironment(simulator)
    /// A camera state the Simulator can't produce, shown with `-camera-scenario <name>`.
    enum CameraScenario: String {
        case denied, restricted, failed
        case inUse = "in-use"
        case multitasking, overheated, critical

        static var launched: CameraScenario? {
            UserDefaults.standard.string(forKey: LaunchArgument.cameraScenario).flatMap(CameraScenario.init)
        }

        private static let eventDelay = Duration.seconds(2)

        func makeSource() -> MockCameraSource {
            if let startError { return MockCameraSource(failingStartWith: startError) }
            let source = MockCameraSource()
            if let event {
                Task {
                    try? await Task.sleep(for: Self.eventDelay)
                    await source.emit(event)
                }
            }
            return source
        }

        private var startError: CameraError? {
            switch self {
            case .denied: .notAuthorized
            case .restricted: .restricted
            default: nil
            }
        }

        private var event: CameraEvent? {
            switch self {
            case .failed: .failed
            case .inUse: .interrupted(.inUseByAnotherApp)
            case .multitasking: .interrupted(.multipleForegroundApps)
            case .overheated: .interrupted(.systemPressure)
            case .critical: .pressure(.critical)
            default: nil
            }
        }
    }
#endif
