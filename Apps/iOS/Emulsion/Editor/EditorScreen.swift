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

/// The easy editor: the photo as large as possible, with one group of sliders at a time.
/// Side by side when there's width to spare (landscape, iPhone Duo unfolded), stacked
/// otherwise. One `AnyLayout` for both, so the panel keeps its state when the shape changes.
private struct EditorContent: View {
    @Bindable var session: EditSession

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isShowingOriginal = false
    @State private var panelHeight: CGFloat = 0
    /// Fits the longest slider label at the largest standard text size beside the photo.
    private let sidePanelWidth: CGFloat = 360
    /// Stacked, the photo keeps at least half the height; at accessibility text sizes the
    /// panel scrolls instead of shrinking the photo further.
    private let maximumPanelFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            layout {
                ComparablePhoto(url: session.url, adjustments: session.adjustments, isComparing: isShowingOriginal)
                    .padding(FilmLabLayout.inset)
                controls
                    .frame(maxWidth: isWide ? sidePanelWidth : .infinity)
                    .frame(height: isWide ? nil : min(panelHeight, geometry.size.height * maximumPanelFraction))
            }
        }
        .background(.black)
        // An intentionally neutral dark workspace keeps the photograph visually central.
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorToolbar(session: session, isShowingOriginal: $isShowingOriginal) }
    }

    private var controls: some View {
        ScrollView {
            AdjustmentPanel(adjustments: $session.adjustments)
                .padding([.horizontal, .bottom], FilmLabLayout.inset)
                .padding(.top, isWide ? FilmLabLayout.inset : 0)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { panelHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
