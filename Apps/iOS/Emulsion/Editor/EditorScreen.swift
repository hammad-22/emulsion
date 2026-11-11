import EmulsionKit
import EmulsionUI
import SwiftUI

/// Opens an edit session for the photo and closes it (saving the last change) on the way out.
struct EditorScreen: View {
    let photoID: PhotoRecord.ID

    @Environment(PhotoStore.self) private var store
    @State private var session: EditSession?

    var body: some View {
        Group {
            if let session {
                EditorContent(session: session)
            } else if store.photo(photoID) == nil {
                ContentUnavailableView("Photo Deleted", systemImage: "photo")
            }
        }
        .task {
            if session == nil, let photo = store.photo(photoID) { session = EditSession(photo: photo, store: store) }
        }
        .onDisappear { session?.close() }
    }
}

/// One selected adjustment, revealed beside the photo in the current landscape fallback
/// or below it in portrait. Duo's reserved-region layout remains MOV-119.
private struct EditorContent: View {
    @Bindable var session: EditSession

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var group = AdjustmentGroup.light
    @State private var selection: [AdjustmentGroup: String] = [:]
    @State private var isComparing = false
    @State private var isHolding = false
    @State private var showsAdjustments = false
    /// Gives the ruler useful travel beside the photo in landscape.
    private let sidePanelWidth: CGFloat = 360
    /// Stacked, the photo keeps at least half the height; at accessibility text sizes the
    /// panel scrolls instead of shrinking the photo further.
    private let maximumPanelFraction: CGFloat = 0.5

    private var showsOriginal: Bool { isComparing || isHolding }

    var body: some View {
        GeometryReader { geometry in
            layout {
                ComparablePhoto(url: session.url, adjustments: session.adjustments, isComparing: isComparing, isHolding: $isHolding)
                    .padding(isWide ? FilmLabLayout.inset : 0)
                controls
                    .disabled(showsOriginal)
                    .frame(
                        maxWidth: isWide ? (showsAdjustments ? sidePanelWidth : 0) : .infinity,
                        maxHeight: showsAdjustments ? (isWide ? .infinity : geometry.size.height * maximumPanelFraction) : 0
                    )
                    .fixedSize(horizontal: false, vertical: !isWide)
                    .layoutPriority(1)
            }
        }
        .background(.black)
        // An intentionally neutral dark workspace keeps the photograph visually central.
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle(showsOriginal ? Text("Original") : Text(""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorToolbar(session: session, isComparing: $isComparing, showsAdjustments: $showsAdjustments) }
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
        AdjustmentPanel(adjustments: $session.adjustments, group: $group, selection: $selection)
            .padding(.horizontal, FilmLabLayout.inset)
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
