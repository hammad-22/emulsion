import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// The phone editor: the photo with one ruler's panel below it, or beside it in landscape,
/// revealed by Adjust.
struct CompactEditorLayout<Photo: View>: View {
    /// The height available, which caps the stacked panel.
    let height: CGFloat
    let showsAdjustments: Bool
    let isEditable: Bool
    let whiteBalanceAsShot: CameraWhiteBalance?
    @Binding var adjustments: Adjustments
    @Binding var group: AdjustmentGroup
    @Binding var selection: [AdjustmentGroup: String]
    @ViewBuilder let photo: () -> Photo

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Gives the ruler useful travel beside the photo in landscape.
    private let sidePanelWidth: CGFloat = 360
    /// Stacked, the photo keeps at least half the height; at accessibility text sizes the
    /// panel scrolls instead of shrinking the photo further.
    private let maximumPanelFraction: CGFloat = 0.5

    var body: some View {
        layout {
            photo().padding(isWide ? FilmLabLayout.inset : 0)
            controls
                .disabled(!isEditable)
                .frame(
                    maxWidth: isWide ? (showsAdjustments ? sidePanelWidth : 0) : .infinity,
                    maxHeight: showsAdjustments ? (isWide ? .infinity : height * maximumPanelFraction) : 0
                )
                .fixedSize(horizontal: false, vertical: !isWide)
                .layoutPriority(1)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .vertical) {
            panel
            ScrollView { panel }
        }
        .frame(height: showsAdjustments ? nil : 0)
        .clipped()
        .opacity(showsAdjustments ? 1 : 0)
        .allowsHitTesting(showsAdjustments)
        .accessibilityHidden(!showsAdjustments)
    }

    private var panel: some View {
        AdjustmentPanel(adjustments: $adjustments, group: $group, selection: $selection, whiteBalanceAsShot: whiteBalanceAsShot)
            .padding(.horizontal, FilmLabLayout.inset)
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
