import EmulsionKit
import EmulsionUI
import SwiftUI

/// Square thumbnails that fill the width: three across on iPhone, more on wider canvases.
struct PhotoGrid: View {
    @Environment(PhotoStore.self) private var store

    /// Three columns on a 402 pt wide iPhone; more as the canvas widens.
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: Self.hairline)]
    private static let hairline: CGFloat = 2

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Self.hairline) {
                ForEach(store.photos) { photo in
                    NavigationLink(value: photo.id) {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { RenderedPhoto(url: store.url(for: photo), adjustments: photo.adjustments, contentMode: .fill) }
                            .clipped()
                    }
                    .accessibilityLabel(Text("Photo from \(photo.created, format: .dateTime.day().month().year())"))
                }
            }
        }
    }
}
