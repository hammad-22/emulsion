import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct CompactEditorLayout<Photo: View>: View {
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
    private let sidePanelWidth: CGFloat = 360
    private let maximumPanelFraction: CGFloat = 0.5

    @State private var panelHeight: CGFloat = 0

    var body: some View {
        layout {
            photo().padding(isWide ? FilmLabLayout.inset : 0)
            controls
                .disabled(!isEditable)
                .frame(maxWidth: isWide ? (showsAdjustments ? sidePanelWidth : 0) : .infinity)
                .layoutPriority(1)
        }
    }

    private var controls: some View {
        ScrollView {
            panel.onGeometryChange(for: CGFloat.self, of: \.size.height) { panelHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .frame(height: controlsHeight)
        .clipped()
        .opacity(showsAdjustments ? 1 : 0)
        .allowsHitTesting(showsAdjustments)
        .accessibilityHidden(!showsAdjustments)
    }

    private var panel: some View {
        AdjustmentPanel(adjustments: $adjustments, group: $group, selection: $selection, whiteBalanceAsShot: whiteBalanceAsShot)
            .padding(.horizontal, FilmLabLayout.inset)
    }

    private var controlsHeight: CGFloat? {
        guard showsAdjustments else { return 0 }
        return isWide ? nil : min(panelHeight, height * maximumPanelFraction)
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
