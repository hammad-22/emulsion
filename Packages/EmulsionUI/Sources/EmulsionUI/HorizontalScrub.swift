import SwiftUI

extension View {
    /// A horizontal drag that leaves vertical drags to an enclosing scroll view. `onChanged`
    /// receives the translation since the drag began.
    func horizontalScrub(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping () -> Void) -> some View {
        #if os(iOS)
            // A SwiftUI DragGesture claims the touch before the scroll view's pan can start, even
            // when the drag is vertical; a UIKit pan that declines to begin hands it over.
            gesture(HorizontalPanGesture(onChanged: onChanged, onEnded: onEnded))
        #else
            simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { onChanged($0.translation) }
                    .onEnded { _ in onEnded() }
            )
        #endif
    }
}

#if os(iOS)
    import UIKit

    /// A pan that only begins when it starts out more horizontal than vertical.
    private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
        let onChanged: (CGSize) -> Void
        let onEnded: () -> Void

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

        func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
            let pan = UIPanGestureRecognizer()
            pan.delegate = context.coordinator
            return pan
        }

        func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
            switch recognizer.state {
            case .began, .changed:
                let translation = recognizer.translation(in: recognizer.view)
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y)
            }
        }
    }
#endif
