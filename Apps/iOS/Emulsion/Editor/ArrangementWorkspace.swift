import EmulsionUI
import SwiftUI

@available(iOS 27.1, *)
struct ArrangementWorkspace<Photo: View, Inspector: View>: View {
    let showsInspector: Bool
    @ViewBuilder let photo: () -> Photo
    @ViewBuilder let inspector: () -> Inspector

    private let inspectorMinimumWidth: CGFloat = 320
    private let inspectorIdealWidth: CGFloat = 360

    var body: some View {
        ArrangementView {
            // Alone, the photo spans the whole canvas, so it must step off an active fold itself.
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

    private var splitAxes: Axis.Set { showsInspector ? [.horizontal, .vertical] : [] }
}
