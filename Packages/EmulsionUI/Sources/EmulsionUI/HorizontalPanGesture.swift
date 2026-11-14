#if os(iOS)
    import SwiftUI
    import UIKit

    struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
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
                let start = context.coordinator.start ?? .scrub
                onChanged(start.reported(recognizer.translation(in: recognizer.view)))
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            private(set) var start: ScrubStart?

            func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
                let start = ScrubStart(velocity: pan.velocity(in: pan.view), canScrollVertically: canScrollVertically(under: pan))
                self.start = start
                return start != .yield
            }

            /// Gestures behind the scale wait until this pan decides.
            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
            ) -> Bool {
                guard let view = recognizer.view, let otherView = other.view, otherView !== view else { return false }
                return view.isDescendant(of: otherView)
            }

            /// Walks up from the hit view: SwiftUI may attach the recognizer above the scroll view.
            private func canScrollVertically(under pan: UIPanGestureRecognizer) -> Bool {
                guard let view = pan.view else { return false }
                var ancestor = view.hitTest(pan.location(in: view), with: nil) ?? view
                while true {
                    if let scrollView = ancestor as? UIScrollView, scrollView.isScrollEnabled,
                        scrollView.contentSize.height > scrollView.bounds.height
                    {
                        return true
                    }
                    guard let next = ancestor.superview else { return false }
                    ancestor = next
                }
            }
        }
    }
#endif
