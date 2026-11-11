import SwiftUI

/// Keep the whole photograph and its controls in a usable rectangle, without cropping.
@available(iOS 27.1, *)
struct UnobscuredContent<Content: View>: View {
    var avoidsDivision = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let regions =
                geometry.reservedRegions(kind: .occlusion)
                + (avoidsDivision ? geometry.reservedRegions(kind: .division) : [])
            let frame = WorkspaceRegion.largestRectangle(
                in: CGRect(origin: .zero, size: geometry.size),
                avoiding: regions.map { region in
                    region.frame.inset(
                        by: UIEdgeInsets(
                            top: -region.margins.top, left: -region.margins.leading,
                            bottom: -region.margins.bottom, right: -region.margins.trailing))
                })
            content()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}
