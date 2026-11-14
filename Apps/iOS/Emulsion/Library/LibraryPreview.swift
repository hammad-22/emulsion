import EmulsionKit
import EmulsionUI
import SwiftUI

struct LibraryPreview: View {
    let photoID: PhotoRecord.ID?
    let isSelecting: Bool
    let edit: (PhotoRecord.ID) -> Void

    @Environment(PhotoStore.self) private var store

    var body: some View {
        if let photoID, let photo = store.photo(photoID) {
            VStack(spacing: FilmLabLayout.inset) {
                RenderedPhoto(url: store.url(for: photo), adjustments: photo.adjustments)
                    .accessibilityLabel("Selected photo")
                    .accessibilityAddTraits(.isImage)
                    // A new photo starts fresh rather than keeping the last one's image.
                    .id(photoID)
                PreviewCaption(photo: photo, canEdit: !isSelecting) { edit(photoID) }
            }
            .padding(FilmLabLayout.inset)
        }
    }
}
