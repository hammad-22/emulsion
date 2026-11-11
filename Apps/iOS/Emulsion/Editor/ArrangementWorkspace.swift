import SwiftUI

/// System arrangements own division-region layout; each pane avoids active camera occlusions.
@available(iOS 27.1, *)
struct ArrangementWorkspace<Photo: View, Controls: View>: View {
    let showsControls: Bool
    @ViewBuilder let photo: () -> Photo
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        if showsControls {
            ArrangementView {
                UnobscuredContent { photo() }
            } secondary: {
                UnobscuredContent { controls() }
                    // Preferred ruler width; the system can redistribute space around a division.
                    .splitArrangementLayoutSize(idealWidth: 360)
            }
            .arrangementViewStyle(.split)
        } else {
            UnobscuredContent(avoidsDivision: true) { photo() }
        }
    }
}
