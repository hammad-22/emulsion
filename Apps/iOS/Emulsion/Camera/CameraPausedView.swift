import EmulsionKit
import SwiftUI

/// Over the frozen viewfinder while the system has paused the camera: why, and that it comes
/// back by itself. Blurred, like the system Camera's own pause, rather than an alert.
struct CameraPausedView: View {
    let interruption: CameraInterruption

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("camera-paused")
    }

    private var symbol: String {
        switch interruption {
        case .systemPressure: "thermometer.high"
        case .multipleForegroundApps: "rectangle.split.2x1"
        case .inUseByAnotherApp, .other: "pause.circle"
        }
    }

    private var title: LocalizedStringKey {
        switch interruption {
        case .inUseByAnotherApp: "Camera in Use"
        case .systemPressure: "Camera Cooling Down"
        case .multipleForegroundApps, .other: "Camera Paused"
        }
    }

    private var description: LocalizedStringKey {
        switch interruption {
        case .inUseByAnotherApp: "Another app is using the camera. It comes back when that app lets go."
        case .multipleForegroundApps: "The camera works when Emulsion is the only app on screen."
        case .systemPressure: "iPhone is too warm to use the camera. It comes back when it cools down."
        case .other: "The camera comes back automatically."
        }
    }
}
