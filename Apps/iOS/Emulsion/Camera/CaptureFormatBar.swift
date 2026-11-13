import EmulsionKit
import EmulsionUI
import SwiftUI

/// What the shutter will write: the RAW format, and 12 or 48 MP where the lens offers both.
struct CaptureFormatBar: View {
    let capabilities: CameraCapabilities?

    @Environment(AppSettings.self) private var settings

    var body: some View {
        GlassEffectContainer {
            HStack {
                if let capabilities {
                    Text(capabilities.rawFormat.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, FilmLabLayout.gap)
                        .frame(minHeight: 34)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityLabel("Format: \(capabilities.rawFormat.title)")
                    resolution(capabilities)
                }
            }
        }
        .frame(minHeight: FilmLabLayout.minimumControlHeight)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
