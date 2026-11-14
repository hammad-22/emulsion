import SwiftUI

extension View {
    /// A horizontal drag that leaves vertical drags to an enclosing scroll view that can
    /// scroll. `onChanged` receives the translation since the drag began, as `ScrubStart`
    /// reports it on iOS.
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
