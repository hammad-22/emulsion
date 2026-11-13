import EmulsionKit
import SwiftUI
import UIKit

/// In place of the viewfinder when the camera can't run; the library stays reachable.
struct CameraUnavailableView: View {
    enum Reason {
        /// The user turned camera access off; Settings can turn it back on.
        case denied
        /// Screen Time or a management profile blocks the camera; Emulsion's settings can't help.
        case restricted
        /// The camera failed; starting it again may work.
        case unavailable(retry: () -> Void)
    }

    let reason: Reason

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera")
        } description: {
            Text(description)
        } actions: {
            switch reason {
            case .denied:
                // A constant system URL.
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    .buttonStyle(.glass)
            case .restricted:
                EmptyView()
            case .unavailable(let retry):
                Button("Try Again", action: retry)
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: LocalizedStringKey {
        switch reason {
        case .denied: "Camera Access Needed"
        case .restricted: "Camera Restricted"
        case .unavailable: "Camera Unavailable"
        }
    }

    private var description: LocalizedStringKey {
        switch reason {
        case .denied: "Allow Emulsion to use the camera in Settings to take RAW photos."
        case .restricted: "Camera access is restricted on this iPhone, for example by Screen Time. Your library is still available."
        case .unavailable: "The camera can't be used right now. Your library is still available."
        }
    }
}
