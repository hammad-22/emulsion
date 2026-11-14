import EmulsionKit
import EmulsionUI
import SwiftUI

struct PhotoCell: View {
    let photo: PhotoRecord
    let isPreviewed: Bool
    @Binding var selection: LibrarySelection
    let edit: (PhotoRecord.ID) -> Void
    let activate: (PhotoRecord.ID) -> Void

    @Environment(PhotoStore.self) private var store
    /// Lightens a picked thumbnail, as Photos does, without hiding the photograph.
    private let selectedWash = 0.3

    private var isSelected: Bool { selection.photos.contains(photo.id) }

    var body: some View {
        Button {
            if selection.isActive { selection.toggle(photo.id) } else { activate(photo.id) }
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
        // The time tells apart photos taken the same day, as Photos does.
        .accessibilityLabel(Text("Photo from \(photo.created, format: .dateTime.day().month().year().hour().minute())"))
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
}
