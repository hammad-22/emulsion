import EmulsionKit
import EmulsionUI
import SwiftUI

struct EditorContent: View {
    @Bindable var session: EditSession

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var group = AdjustmentGroup.light
    @State private var selection: [AdjustmentGroup: String] = [:]
    @State private var isComparing = false
    @State private var isHolding = false
    /// Nil until the user taps Adjust; until then the canvas decides.
    @State private var adjustmentsPreference: Bool?

    private var showsOriginal: Bool { isComparing || isHolding }
    private let verticalPanelWidth: CGFloat = 128
    private let minimumVerticalPanelHeight: CGFloat = 250

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = geometry.isExpandedCanvas(horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
            let showsAdjustments = adjustmentsPreference ?? isExpanded
            workspace(geometry, isExpanded: isExpanded, showsAdjustments: showsAdjustments)
                .toolbar {
                    EditorToolbar(session: session, isComparing: $isComparing, showsAdjustments: showsAdjustments) {
                        adjustmentsPreference = !showsAdjustments
                    }
                }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle(showsOriginal ? Text("Original") : Text(""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.editorAppeared() }
    }

    @ViewBuilder
    private func workspace(_ geometry: GeometryProxy, isExpanded: Bool, showsAdjustments: Bool) -> some View {
        if #available(iOS 27.1, *) {
            EditorAdjustmentAxis(hasDivision: !geometry.reservedRegions(kind: .division, options: .includeInactive).isEmpty) { vertical in
                adaptiveWorkspace(
                    isExpanded: isExpanded, showsAdjustments: showsAdjustments,
                    usesVerticalPanel: vertical && geometry.size.height >= minimumVerticalPanelHeight)
            }
        } else {
            compactLayout(height: geometry.size.height, showsAdjustments: showsAdjustments)
        }
    }

    @available(iOS 27.1, *)
    @ViewBuilder private func adaptiveWorkspace(isExpanded: Bool, showsAdjustments: Bool, usesVerticalPanel: Bool) -> some View {
        if isExpanded {
            ArrangementWorkspace(showsInspector: showsAdjustments, narrowInspectorWidth: usesVerticalPanel ? verticalPanelWidth : nil) {
                photo.padding(FilmLabLayout.inset)
            } inspector: {
                if usesVerticalPanel {
                    verticalPanel
                } else {
                    AdjustmentInspector(
                        adjustments: $session.adjustments, group: $group, selection: $selection,
                        whiteBalanceAsShot: session.asShotWhiteBalance
                    )
                    .disabled(showsOriginal)
                }
            }
        } else if usesVerticalPanel {
            UnobscuredContent {
                HStack(spacing: showsAdjustments ? FilmLabLayout.compact : 0) {
                    photo
                    verticalPanel
                        .frame(width: showsAdjustments ? verticalPanelWidth : 0)
                        .clipped()
                        .opacity(showsAdjustments ? 1 : 0)
                        .allowsHitTesting(showsAdjustments)
                        .accessibilityHidden(!showsAdjustments)
                }
                .padding(.horizontal, FilmLabLayout.compact)
            }
        } else {
            // Always wrapped, so an occlusion appearing doesn't rebuild the photo.
            UnobscuredContent {
                GeometryReader { unobscured in
                    compactLayout(height: unobscured.size.height, showsAdjustments: showsAdjustments)
                }
            }
        }
    }

    private var verticalPanel: some View {
        VerticalAdjustmentPanel(
            adjustments: $session.adjustments, group: $group, selection: $selection,
            whiteBalanceAsShot: session.asShotWhiteBalance
        )
        .frame(maxWidth: verticalPanelWidth)
        .disabled(showsOriginal)
    }

    private var photo: some View {
        ComparablePhoto(url: session.url, adjustments: session.adjustments, isComparing: isComparing, isHolding: $isHolding)
    }

    private func compactLayout(height: CGFloat, showsAdjustments: Bool) -> some View {
        CompactEditorLayout(
            height: height, showsAdjustments: showsAdjustments, isEditable: !showsOriginal,
            whiteBalanceAsShot: session.asShotWhiteBalance, adjustments: $session.adjustments, group: $group, selection: $selection
        ) {
            photo
        }
    }
}
