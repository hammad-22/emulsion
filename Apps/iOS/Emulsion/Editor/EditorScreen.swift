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

/// The easy editor: the photo as large as possible on a neutral black surround, with one
/// group of sliders on a floating glass panel. The panel sits beside the photo when there's
/// width to spare (landscape, iPhone Duo unfolded) and below it otherwise, never over it.
/// One `AnyLayout` for both, so the photo and panel keep their state when the shape changes.
private struct EditorContent: View {
    @Bindable var session: EditSession

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var group = AdjustmentGroup.light
    @State private var isComparing = false
    @State private var isHolding = false
    /// Fits the longest slider row at the largest standard text size beside the photo.
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
                panel
                    .disabled(showsOriginal)
                    .frame(
                        maxWidth: isWide ? sidePanelWidth : .infinity,
                        maxHeight: isWide ? .infinity : geometry.size.height * maximumPanelFraction
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
        .toolbar { EditorToolbar(session: session, isComparing: $isComparing) }
    }

    /// The panel at its own height when that fits, scrolling when it doesn't.
    private var panel: some View {
        ViewThatFits(in: .vertical) {
            adjustmentPanel
            ScrollView { adjustmentPanel }
        }
    }

    private var adjustmentPanel: some View {
        AdjustmentPanel(adjustments: $session.adjustments, group: $group)
            .padding(.horizontal, FilmLabLayout.inset)
            .padding(.vertical, FilmLabLayout.compact)
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
