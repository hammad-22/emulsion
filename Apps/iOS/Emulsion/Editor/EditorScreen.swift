import EmulsionKit
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
        .onAppear {
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
    /// Fits the longest slider label at the largest standard text size beside the photo.
    private let sidePanelWidth: CGFloat = 340

    var body: some View {
        layout {
            ComparablePhoto(url: session.url, adjustments: session.adjustments, isComparing: isShowingOriginal)
                .padding()
            AdjustmentPanel(adjustments: $session.adjustments)
                .frame(maxWidth: isWide ? sidePanelWidth : .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorToolbar(session: session, isShowingOriginal: $isShowingOriginal) }
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    private var layout: AnyLayout {
        isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }
}
