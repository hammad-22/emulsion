import EmulsionKit
import EmulsionUI
import SwiftUI

/// Square thumbnails edge to edge, like a contact sheet.
struct PhotoGrid: View {
    @Binding var selection: LibrarySelection
    let transition: Namespace.ID
    /// A fixed number of columns, or nil for as many cells as fit.
    var columnCount: Int? = nil
    var previewID: PhotoRecord.ID? = nil
    let edit: (PhotoRecord.ID) -> Void
    /// A tap outside Select: opens the editor on iPhone, previews in the expanded library.
    let activate: (PhotoRecord.ID) -> Void

    @Environment(PhotoStore.self) private var store

    /// Three columns on a 402 pt wide iPhone; more as the canvas widens.
    private let minimumCellWidth: CGFloat = 110
    private var adaptiveColumn: GridItem { GridItem(.adaptive(minimum: minimumCellWidth), spacing: FilmLabLayout.gridSpacing) }

    private var columns: [GridItem] {
        guard let columnCount else { return [adaptiveColumn] }
        return Array(repeating: GridItem(.flexible(), spacing: FilmLabLayout.gridSpacing), count: columnCount)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: FilmLabLayout.gridSpacing) {
                ForEach(store.photos) { photo in
                    PhotoCell(photo: photo, isPreviewed: previewID == photo.id, selection: $selection, edit: edit, activate: activate)
                        .matchedTransitionSource(id: photo.id, in: transition)
                }
            }
        }
    }
}
