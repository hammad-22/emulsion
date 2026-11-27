import SwiftUI

@available(iOS 27.1, *)
struct EditorAdjustmentAxis<Content: View>: View {
    let hasDivision: Bool
    @ViewBuilder let content: (Bool) -> Content

    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        content((hasDivision || verticalEdge != nil) && !textSize.isAccessibilitySize)
    }
}
