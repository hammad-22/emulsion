import EmulsionUI
import SwiftUI

/// Keep the whole photograph and its controls in a usable rectangle, without cropping.
@available(iOS 27.1, *)
struct UnobscuredContent<Content: View>: View {
    var avoidsDivision = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            // Frames include safety margins; use physical coordinates for explicit positioning.
            let regions =
                geometry.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
                + (avoidsDivision ? geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed) : [])
            let frame = WorkspaceRegion.largestRectangle(
                in: CGRect(origin: .zero, size: geometry.size),
                avoiding: regions.map(\.frame))
            content()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}
