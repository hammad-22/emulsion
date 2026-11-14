import SwiftUI

extension View {
    /// A horizontal drag that leaves vertical drags to a scroll view; see `ScrubStart`.
    func horizontalScrub(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping () -> Void) -> some View {
        #if os(iOS)
            // A SwiftUI DragGesture would claim vertical drags before the scroll view could.
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
