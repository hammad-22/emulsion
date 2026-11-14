import SwiftUI
import UIKit

@MainActor
final class ViewfinderDisplay {
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

struct ViewfinderLayerView: UIViewRepresentable {
    let display: ViewfinderDisplay

    func makeUIView(context: Context) -> UIView { display.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
