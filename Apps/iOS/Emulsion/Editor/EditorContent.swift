import EmulsionKit
import EmulsionUI
import SwiftUI

/// Owns edit and control selection independently of the current display arrangement.
struct EditorContent: View {
    @Bindable var session: EditSession

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var group = AdjustmentGroup.light
    @State private var selection: [AdjustmentGroup: String] = [:]
    @State private var isComparing = false
    @State private var isHolding = false
    /// Nil until the user taps Adjust: the inspector then follows the canvas, shown when expanded.
    @State private var adjustmentsPreference: Bool?

    private var showsOriginal: Bool { isComparing || isHolding }

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = geometry.isExpandedCanvas(horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
            // The user's last Adjust choice survives folding; until then, the canvas decides.
            let showsAdjustments = adjustmentsPreference ?? isExpanded
            workspace(geometry, isExpanded: isExpanded, showsAdjustments: showsAdjustments)
                .toolbar {
                    EditorToolbar(session: session, isComparing: $isComparing, showsAdjustments: showsAdjustments) {
                        adjustmentsPreference = !showsAdjustments
                    }
                }
        }
        .background(.black)
        // An intentionally neutral dark workspace keeps the photograph visually central.
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle(showsOriginal ? Text("Original") : Text(""))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func workspace(_ geometry: GeometryProxy, isExpanded: Bool, showsAdjustments: Bool) -> some View {
        if #available(iOS 27.1, *), isExpanded {
            ArrangementWorkspace(showsInspector: showsAdjustments) {
                photo.padding(FilmLabLayout.inset)
            } inspector: {
                AdjustmentInspector(
                    adjustments: $session.adjustments, group: $group, selection: $selection,
                    whiteBalanceAsShot: session.asShotWhiteBalance
                )
                .disabled(showsOriginal)
            }
        } else if #available(iOS 27.1, *) {
            // Always wrapped, so an occlusion appearing doesn't rebuild the photo; the panel's
            // height cap is measured in the unobscured rectangle.
            UnobscuredContent {
                GeometryReader { unobscured in
                    compactLayout(height: unobscured.size.height, showsAdjustments: showsAdjustments)
                }
            }
        } else {
            compactLayout(height: geometry.size.height, showsAdjustments: showsAdjustments)
        }
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
