import SwiftUI
import UIKit

/// In place of the viewfinder when the camera can't run; the library stays reachable.
struct CameraUnavailableView: View {
    let isUnauthorized: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(isUnauthorized ? "Camera Access Needed" : "Camera Unavailable", systemImage: "camera")
        } description: {
            Text(
                isUnauthorized
                    ? "Allow Emulsion to use the camera in Settings to take RAW photos."
                    : "The camera can't be used right now. Your library is still available.")
        } actions: {
            if isUnauthorized {
                // A constant system URL.
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
