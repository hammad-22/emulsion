import EmulsionKit
import EmulsionUI
import SwiftUI

/// Portrait: the format bar, the viewfinder, then lenses and the shutter below it.
/// Wide (landscape, iPhone Duo unfolded): the viewfinder on the leading side and the same
/// controls in a trailing rail.
struct CameraContent: View {
    @Bindable var model: CameraModel
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: FilmLabLayout.inset) {
                    stage
                    CameraControls(model: model, axis: .vertical, showsLibrary: $showsLibrary, transition: transition)
                }
            } else {
                VStack(spacing: FilmLabLayout.gap) {
                    CaptureFormatBar(capabilities: model.capabilities, axis: .horizontal)
                    stage
                    CameraControls(model: model, axis: .horizontal, showsLibrary: $showsLibrary, transition: transition)
                }
            }
        }
        .padding(FilmLabLayout.inset)
        .alert("Couldn't Take Photo", isPresented: Binding(isPresenting: $model.error), presenting: model.error) { _ in
        } message: {
            Text($0.localizedDescription)
        }
    }

    @ViewBuilder private var stage: some View {
        switch model.status {
        case .unauthorized, .unavailable:
            CameraUnavailableView(isUnauthorized: model.status == .unauthorized)
        default:
            ViewfinderView(model: model)
        }
    }

    /// The same rule as the editor: a regular-width or compact-height canvas.
    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
}
