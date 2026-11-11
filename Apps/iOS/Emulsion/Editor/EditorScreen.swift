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
