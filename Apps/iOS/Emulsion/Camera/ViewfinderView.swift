import EmulsionKit
import EmulsionUI
import SwiftUI

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
    private let timingOverlayPadding: CGFloat = 8

    var body: some View {
        ViewfinderLayerView(display: display)
            .aspectRatio(aspectRatio ?? uprightAspectRatioBeforeFirstFrame, contentMode: .fit)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .overlay { FocusReticle(point: model.focusPoint) }
            .overlay(alignment: .topLeading) { timingOverlay }
            .modifier(ShutterBlink(captureCount: model.captureCount))
            .contentShape(.rect)
            .onTapGesture { focus(at: $0) }
            .accessibilityElement()
            .accessibilityLabel("Viewfinder")
            .accessibilityHint("Double-tap to focus and expose on the centre")
            .accessibilityAction { focus(at: CGPoint(x: size.width / 2, y: size.height / 2)) }
            .accessibilityIdentifier(AccessibilityID.viewfinder)
            // Outside the viewfinder's element, so VoiceOver reads why the camera paused.
            .overlay { paused }
            .overlay(alignment: .top) { coolingNote }
            .overlay(alignment: .bottom) { accessory }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await model.attachViewfinder(ViewfinderLayer(display.view.layer)) }
            .task(id: pixels) { await showFrames(maxDimension: pixels) }
    }

    @ViewBuilder private var paused: some View {
        if case .interrupted(let interruption) = model.status {
            CameraPausedView(interruption: interruption)
        }
    }

    @ViewBuilder private var coolingNote: some View {
        if model.pressure >= .critical { CoolingNote().padding(FilmLabLayout.gap) }
    }

    @ViewBuilder private var timingOverlay: some View {
        #if DEBUG
            if ViewfinderTimingOverlay.isEnabled { ViewfinderTimingOverlay(model: model).padding(timingOverlayPadding) }
        #endif
    }

    private var uprightAspectRatioBeforeFirstFrame: CGFloat { verticalSizeClass == .compact ? 4 / 3 : 3 / 4 }

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

private struct ShutterBlink: ViewModifier {
    let captureCount: Int

    private let peakOpacity = 0.8
    private let closeDuration = 0.04
    private let openDuration = 0.18

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: captureCount) { view, blink in
            view.overlay { Color.black.opacity(blink).allowsHitTesting(false) }
        } keyframes: { _ in
            LinearKeyframe(peakOpacity, duration: closeDuration)
            LinearKeyframe(0, duration: openDuration)
        }
    }
}
