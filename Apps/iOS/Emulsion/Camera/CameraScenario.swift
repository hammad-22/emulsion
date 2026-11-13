import EmulsionKit
import Foundation

#if DEBUG && targetEnvironment(simulator)
    /// A camera state the Simulator can't produce on its own, for checking how the screen shows
    /// it. Launch with `-camera-scenario <name>`, e.g. `-camera-scenario in-use`.
    enum CameraScenario: String {
        case denied, restricted, failed
        case inUse = "in-use"
        case multitasking, overheated, critical

        static var launched: CameraScenario? {
            UserDefaults.standard.string(forKey: "camera-scenario").flatMap(CameraScenario.init)
        }

        /// The stand-in camera, reporting the scenario's event once the viewfinder has shown a
        /// moment of frames.
        func makeSource() -> MockCameraSource {
            if let startError { return MockCameraSource(failingStartWith: startError) }
            let source = MockCameraSource()
            if let event {
                Task {
                    try? await Task.sleep(for: .seconds(2))
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
