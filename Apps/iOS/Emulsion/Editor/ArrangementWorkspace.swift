import EmulsionUI
import SwiftUI

/// The photo beside the full adjustment inspector, with the system arrangement owning the
/// division. Hiding the inspector drops the split's axes rather than the arrangement, so the
/// photo view, and its last render, stay in place.
@available(iOS 27.1, *)
struct ArrangementWorkspace<Photo: View, Inspector: View>: View {
    let showsInspector: Bool
    @ViewBuilder let photo: () -> Photo
    @ViewBuilder let inspector: () -> Inspector

    /// Rulers keep useful travel; the system can redistribute space around a division.
    private let inspectorMinimumWidth: CGFloat = 320
    private let inspectorIdealWidth: CGFloat = 360

    var body: some View {
        ArrangementView {
            // Alone, the photo spans the whole canvas, so it steps off an active fold itself.
            UnobscuredContent(avoidsDivision: !showsInspector) { photo() }
        } secondary: {
            UnobscuredContent {
                inspector()
                    .padding(FilmLabLayout.inset)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .splitArrangementLayoutSize(minWidth: inspectorMinimumWidth, idealWidth: inspectorIdealWidth)
        }
        .arrangementViewStyle(.split.axes(splitAxes))
    }

    /// A split without an axis shows only the primary.
    private var splitAxes: Axis.Set { showsInspector ? [.horizontal, .vertical] : [] }
}
