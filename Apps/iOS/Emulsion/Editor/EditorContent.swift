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
    /// Gives the ruler useful travel beside the photo in landscape.
    private let sidePanelWidth: CGFloat = 360
    /// Stacked, the photo keeps at least half the height; at accessibility text sizes the
    /// panel scrolls instead of shrinking the photo further.
    private let maximumPanelFraction: CGFloat = 0.5

    private var showsOriginal: Bool { isComparing || isHolding }

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = geometry.isExpandedCanvas(horizontalSizeClass: horizontalSizeClass)
            let showsAdjustments = adjustmentsVisibility(isExpanded: isExpanded)
            workspace(geometry, isExpanded: isExpanded, showsAdjustments: showsAdjustments.wrappedValue)
                .toolbar { EditorToolbar(session: session, isComparing: $isComparing, showsAdjustments: showsAdjustments) }
        }
        .background(.black)
        // An intentionally neutral dark workspace keeps the photograph visually central.
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle(showsOriginal ? Text("Original") : Text(""))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The user's last Adjust choice, which survives folding; until then, the canvas default.
    private func adjustmentsVisibility(isExpanded: Bool) -> Binding<Bool> {
        Binding(get: { adjustmentsPreference ?? isExpanded }, set: { adjustmentsPreference = $0 })
    }

    @ViewBuilder
    private func workspace(_ geometry: GeometryProxy, isExpanded: Bool, showsAdjustments: Bool) -> some View {
        if #available(iOS 27.1, *), isExpanded {
            ArrangementWorkspace(showsInspector: showsAdjustments) {
                photo.padding(FilmLabLayout.inset)
            } inspector: {
                AdjustmentInspector(adjustments: $session.adjustments, group: $group, selection: $selection)
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
        layout {
            photo.padding(isWide ? FilmLabLayout.inset : 0)
            controls(showsAdjustments: showsAdjustments)
                .disabled(showsOriginal)
                .frame(
                    maxWidth: isWide ? (showsAdjustments ? sidePanelWidth : 0) : .infinity,
                    maxHeight: showsAdjustments ? (isWide ? .infinity : height * maximumPanelFraction) : 0
                )
                .fixedSize(horizontal: false, vertical: !isWide)
                .layoutPriority(1)
        }
    }

    private func controls(showsAdjustments: Bool) -> some View {
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
        AdjustmentPanel(adjustments: $session.adjustments, group: $group, selection: $selection)
            .padding(.horizontal, FilmLabLayout.inset)
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
