import SwiftUI

extension View {
    /// Shows a label's title in a horizontal toolbar; a vertical one keeps the icon-only default.
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
