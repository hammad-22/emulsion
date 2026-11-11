import EmulsionKit
import EmulsionUI
import SwiftUI

/// Square thumbnails edge to edge, like a contact sheet: three across on iPhone, or a fixed
/// count beside the expanded library's preview. A tap previews or opens an edit, or picks the photo while selecting.
struct PhotoGrid: View {
    @Binding var selection: LibrarySelection
    let transition: Namespace.ID
    /// A fixed number of columns, or nil for as many 110 pt cells as fit.
    var columnCount: Int? = nil
    var previewID: PhotoRecord.ID? = nil
    let edit: (PhotoRecord.ID) -> Void
    let open: (PhotoRecord.ID) -> Void

    @Environment(PhotoStore.self) private var store

    /// Three columns on a 402 pt wide iPhone; more as the canvas widens.
    private let adaptiveColumn = GridItem(.adaptive(minimum: 110), spacing: FilmLabLayout.gridSpacing)

    private var columns: [GridItem] {
        guard let columnCount else { return [adaptiveColumn] }
        return Array(repeating: GridItem(.flexible(), spacing: FilmLabLayout.gridSpacing), count: columnCount)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: FilmLabLayout.gridSpacing) {
                ForEach(store.photos) { photo in
                    PhotoCell(photo: photo, selection: $selection, open: open, isPreviewed: previewID == photo.id, edit: edit)
                        .matchedTransitionSource(id: photo.id, in: transition)
                }
            }
        }
    }
}

private struct PhotoCell: View {
    let photo: PhotoRecord
    @Binding var selection: LibrarySelection
    let open: (PhotoRecord.ID) -> Void

    let isPreviewed: Bool
    let edit: (PhotoRecord.ID) -> Void

    @Environment(PhotoStore.self) private var store

    private var isSelected: Bool { selection.photos.contains(photo.id) }

    var body: some View {
        Button {
            if selection.isActive { selection.toggle(photo.id) } else { open(photo.id) }
        } label: {
            PhotoThumbnail(url: store.url(for: photo), adjustments: photo.adjustments)
                .overlay {
                    if isPreviewed && !selection.isActive {
                        Rectangle().strokeBorder(Color.primary, lineWidth: FilmLabLayout.hairline)
                    }
                }
                .overlay { if isSelected { Color.white.opacity(selectedWash) } }
                .overlay(alignment: .bottomTrailing) {
                    if selection.isActive { SelectionBadge(isSelected: isSelected) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Photo from \(photo.created, format: .dateTime.day().month().year())"))
        .accessibilityValue(photo.isEdited ? Text("Edited") : Text(""))
        .accessibilityAddTraits(isSelected || (!selection.isActive && isPreviewed) ? .isSelected : [])
        .contextMenu {
            if !selection.isActive {
                Button("Edit", systemImage: "slider.horizontal.3") { edit(photo.id) }
                Button("Select", systemImage: "checkmark.circle") { selection.begin(with: photo.id) }
                Button("Delete", systemImage: "trash", role: .destructive) { selection.pendingDeletion = [photo.id] }
            }
        }
    }

    /// Lightens a picked thumbnail, as Photos does, without hiding the photograph.
    private let selectedWash = 0.3
}
