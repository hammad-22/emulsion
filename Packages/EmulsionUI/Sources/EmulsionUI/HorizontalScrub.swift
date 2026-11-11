import SwiftUI

#if os(iOS)
    import UIKit
#endif

extension View {
    /// A horizontal drag that leaves vertical drags to an enclosing scroll view that can
    /// scroll. `onChanged` receives the translation since the drag began. On iOS a drag that
    /// starts horizontally (or still) reports no vertical travel, as its direction is already
    /// decided; a vertical drag with no scroll view to take it is claimed, so nothing behind
    /// moves, and reports its full translation for `RulerDrag` to ignore. On macOS it reports
    /// the full translation.
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
    /// A pan that decides once, as it starts, whether to scrub, claim or yield (`ScrubStart`).
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

            /// Gestures on views behind the scale (a navigation dismiss, say) wait until this
            /// pan has decided; when it yields, they proceed.
            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
            ) -> Bool {
                guard let view = recognizer.view, let otherView = other.view, otherView !== view else { return false }
                return view.isDescendant(of: otherView)
            }

            /// Walks up from the view under the touch: SwiftUI may attach the recognizer to a
            /// host view above the scroll view rather than inside it.
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
