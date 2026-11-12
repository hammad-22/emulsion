import EmulsionKit
import EmulsionUI
import SwiftUI

/// Lenses, the shutter and the library. A row under the viewfinder in portrait; a
/// vertical rail, with the format bar at its top, beside it when wide.
struct CameraControls: View {
    let model: CameraModel
    let axis: Axis
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID

    @Environment(PhotoStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        controls
            // Like the system Camera, controls stop growing at the largest accessibility
            // sizes so the viewfinder keeps its room; long-press shows each label large.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder private var controls: some View {
        if axis == .vertical {
            // At accessibility text sizes the rail can outgrow a short screen; it scrolls
            // then instead of clipping.
            ViewThatFits(in: .vertical) {
                rail
                ScrollView { rail }.scrollIndicators(.hidden)
            }
        } else {
            VStack(spacing: FilmLabLayout.space) {
                lenses
                HStack {
                    library
                    Spacer()
                    shutter
                    Spacer()
                    // Balances the library button so the shutter sits centred.
                    Color.clear.frame(width: LibraryButton.size, height: LibraryButton.size)
                }
            }
        }
    }

    private var rail: some View {
        VStack(spacing: FilmLabLayout.gap) {
            CaptureFormatBar(capabilities: model.capabilities, axis: .vertical)
            Spacer(minLength: FilmLabLayout.gap)
            lenses
            shutter
            Spacer(minLength: FilmLabLayout.gap)
            library
        }
    }

    @ViewBuilder private var lenses: some View {
        if let capabilities = model.capabilities, capabilities.lenses.count > 1 {
            LensPicker(capabilities: capabilities, axis: axis) { lens in Task { await model.select(lens) } }
        }
    }

    private var shutter: some View {
        ShutterButton(isEnabled: model.status == .running && !model.isCapturing, captureCount: model.captureCount) {
            Task { await model.capture(resolution: settings.resolution) }
        }
    }

    private var library: some View {
        LibraryButton(photo: model.lastCapture ?? store.photos.first, transition: transition) { showsLibrary = true }
    }
}
