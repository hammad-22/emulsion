import EmulsionKit
import SwiftUI
import UIKit

struct CameraUnavailableView: View {
    enum Reason {
        case denied
        /// Screen Time or a management profile blocks the camera; Emulsion's settings can't help.
        case restricted
        case unavailable(retry: () -> Void)
    }

    let reason: Reason

    @Environment(\.openURL) private var openURL
    // Force unwrap: a constant system URL.
    private static let settingsURL = URL(string: UIApplication.openSettingsURLString)!

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera")
        } description: {
            Text(description)
        } actions: {
            switch reason {
            case .denied:
                Button("Open Settings") { openURL(Self.settingsURL) }
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
