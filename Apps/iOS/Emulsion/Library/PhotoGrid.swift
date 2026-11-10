import EmulsionKit
import EmulsionUI
import SwiftUI

/// Rounded square thumbnails that fill the width: three across on iPhone, more on wider
/// canvases. Each one zooms into the editor.
struct PhotoGrid: View {
    let transition: Namespace.ID

    @Environment(PhotoStore.self) private var store

    /// Three columns on a 402 pt wide iPhone; more as the canvas widens.
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: FilmLabLayout.hairline)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: FilmLabLayout.hairline) {
                ForEach(store.photos) { photo in
                    NavigationLink(value: photo.id) {
                        PhotoThumbnail(url: store.url(for: photo), adjustments: photo.adjustments)
                            .matchedTransitionSource(id: photo.id, in: transition)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Photo from \(photo.created, format: .dateTime.day().month().year())"))
                }
            }
            .padding(.horizontal, FilmLabLayout.inset)
        }
    }
}
