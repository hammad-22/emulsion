import EmulsionKit
import EmulsionUI
import SwiftUI

struct CaptureFormatBar: View {
    let model: CameraModel

    @Environment(AppSettings.self) private var settings

    var body: some View {
        GlassEffectContainer {
            HStack {
                if let capabilities = model.capabilities {
                    Text(capabilities.rawFormat.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, FilmLabLayout.gap)
                        .frame(minHeight: 34)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityLabel("Format: \(capabilities.rawFormat.title)")
                    resolution(capabilities)
                    if let exposure = capabilities.exposure {
                        ExposureMenu(exposure: exposure) { change in
                            Task { await model.changeExposure(change) }
                        }
                        .disabled(!model.acceptsInput)
                    }
                }
            }
        }
        .frame(minHeight: FilmLabLayout.minimumControlHeight)
        .dynamicTypeSize(...FilmLabLayout.largestCameraTextSize)
        .accessibilityShowsLargeContentViewer()
    }

    private func resolution(_ capabilities: CameraCapabilities) -> some View {
        let shown = capabilities.resolution(for: settings.resolution)
        let supportsFull = capabilities.supportsFullResolution
        return Button {
            settings.resolution = settings.resolution == .full ? .standard : .full
        } label: {
            Text(shown.title)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .buttonStyle(.glass)
        .disabled(!supportsFull)
        .accessibilityLabel("Resolution")
        .accessibilityValue(shown.title)
        .accessibilityHint(supportsFull ? "Switches between 12 and 48 megapixels" : "This lens captures at 12 megapixels")
    }
}
