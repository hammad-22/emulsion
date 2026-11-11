import EmulsionKit
import SwiftUI

/// What the shutter will write: the RAW format, and 12 or 48 MP where the lens offers both.
struct CaptureFormatBar: View {
    let capabilities: CameraCapabilities?
    let axis: Axis

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
        GlassEffectContainer {
            layout {
                if let capabilities {
                    Text(capabilities.rawFormat.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityLabel("Format: \(capabilities.rawFormat.title)")
                    resolution(supportsFull: capabilities.supportsFullResolution)
                }
            }
        }
        .frame(minHeight: 44)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityShowsLargeContentViewer()
    }

    private func resolution(supportsFull: Bool) -> some View {
        let shown = supportsFull ? settings.resolution : .standard
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
