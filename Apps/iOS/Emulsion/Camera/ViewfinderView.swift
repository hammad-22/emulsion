import EmulsionKit
import SwiftUI
import UIKit

/// The live camera picture, aspect-fit. Frames go straight into a layer, so 30 frames a
/// second never pass through SwiftUI. Tap to focus and expose there. `accessory` is laid over
/// the picture's bottom edge (the recipe strip), outside the picture's own accessibility element.
struct ViewfinderView<Accessory: View>: View {
    let model: CameraModel
    @ViewBuilder let accessory: Accessory

    @Environment(\.displayScale) private var displayScale
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var display = ViewfinderDisplay()
    @State private var aspectRatio: CGFloat?
    @State private var size = CGSize.zero
    /// Larger frames cost render time without visible gain on a phone.
    private let maxPixels: CGFloat = 1920

    var body: some View {
        ViewfinderLayerView(display: display)
            .aspectRatio(aspectRatio ?? defaultAspectRatio, contentMode: .fit)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .overlay { FocusReticle(point: model.focusPoint) }
            .overlay(alignment: .topLeading) { timingOverlay }
            .keyframeAnimator(initialValue: 0.0, trigger: model.captureCount) { content, blink in
                content.overlay { Color.black.opacity(blink).allowsHitTesting(false) }
            } keyframes: { _ in
                LinearKeyframe(0.8, duration: 0.04)
                LinearKeyframe(0, duration: 0.18)
            }
            .contentShape(.rect)
            .onTapGesture { focus(at: $0) }
            .accessibilityElement()
            .accessibilityLabel("Viewfinder")
            .accessibilityHint("Double-tap to focus and expose on the centre")
            .accessibilityAction { focus(at: CGPoint(x: size.width / 2, y: size.height / 2)) }
            .accessibilityIdentifier("viewfinder")
            .overlay(alignment: .bottom) { accessory }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await model.attachViewfinder(ViewfinderLayer(display.view.layer)) }
            .task(id: pixels) { await showFrames(maxDimension: pixels) }
    }

    @ViewBuilder private var timingOverlay: some View {
        #if DEBUG
            if ViewfinderTimingOverlay.isEnabled { ViewfinderTimingOverlay(model: model).padding(8) }
        #endif
    }

    /// Frames are upright, so portrait 3:4 until the first one says otherwise.
    private var defaultAspectRatio: CGFloat { verticalSizeClass == .compact ? 4 / 3 : 3 / 4 }

    private var pixels: CGFloat { min(max(size.width, size.height) * displayScale, maxPixels).rounded() }

    private func showFrames(maxDimension: CGFloat) async {
        guard maxDimension > 0 else { return }
        for await image in model.viewfinderImages(maxDimension: maxDimension) {
            display.show(image)
            let aspect = CGFloat(image.width) / CGFloat(image.height)
            if aspectRatio != aspect { aspectRatio = aspect }
        }
    }

    private func focus(at location: CGPoint) {
        guard size.width > 0, size.height > 0 else { return }
        let point = CGPoint(x: location.x / size.width, y: location.y / size.height)
        Task { await model.focus(at: point) }
    }
}

/// Owns the layer the frames are drawn into.
@MainActor
private final class ViewfinderDisplay {
    let view = UIView()

    init() {
        view.backgroundColor = .black
        view.layer.contentsGravity = .resizeAspect
        // Taps belong to SwiftUI's gesture, which knows the picture's size.
        view.isUserInteractionEnabled = false
    }

    func show(_ image: CGImage) {
        view.layer.contents = image
    }
}

private struct ViewfinderLayerView: UIViewRepresentable {
    let display: ViewfinderDisplay

    func makeUIView(context: Context) -> UIView { display.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
