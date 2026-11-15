import EmulsionKit
import EmulsionUI
import SwiftUI

struct LibraryButton: View {
    let photo: PhotoRecord?
    let transition: Namespace.ID
    let action: () -> Void

    static let transitionID = "library"
    static let size: CGFloat = 56
    private static let corner: CGFloat = 12

    @Environment(PhotoStore.self) private var store

    var body: some View {
        Button(action: action) {
            Group {
                if let photo {
                    PhotoThumbnail(url: store.url(for: photo), adjustments: photo.adjustments)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassEffect(.regular, in: .rect(cornerRadius: Self.corner))
                }
            }
            .frame(width: Self.size, height: Self.size)
            .clipShape(.rect(cornerRadius: Self.corner))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: Self.transitionID, in: transition)
        .accessibilityLabel("Library")
    }
}
