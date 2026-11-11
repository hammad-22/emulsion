import EmulsionKit
import EmulsionUI
import SwiftUI

struct LibraryPreview: View {
    let photoID: PhotoRecord.ID?
    let edit: (PhotoRecord.ID) -> Void

    @Environment(PhotoStore.self) private var store

    var body: some View {
        if let photoID, let photo = store.photo(photoID) {
            VStack(spacing: FilmLabLayout.inset) {
                RenderedPhoto(url: store.url(for: photo), adjustments: photo.adjustments)
                    .accessibilityLabel("Selected photo")
                    .accessibilityAddTraits(.isImage)
                Button("Edit Photo", systemImage: "dial.low") { edit(photoID) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            .padding(FilmLabLayout.inset)
            .background(.black)
            .preferredColorScheme(.dark)
            .tint(.white)
        }
    }
}
