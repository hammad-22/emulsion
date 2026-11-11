import SwiftUI

extension View {
    /// Shows a toolbar label's title beside its icon in a horizontal bar, and leaves the
    /// system's icon-only default in a vertical bar (iOS 27.1 canvases), where a title would
    /// crowd the column.
    @ViewBuilder
    func titleInHorizontalToolbar() -> some View {
        if #available(iOS 27.1, *) {
            modifier(HorizontalToolbarTitle())
        } else {
            labelStyle(.titleAndIcon)
        }
    }
}

@available(iOS 27.1, *)
private struct HorizontalToolbarTitle: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    func body(content: Content) -> some View {
        if verticalEdge == nil {
            content.labelStyle(.titleAndIcon)
        } else {
            content
        }
    }
}
