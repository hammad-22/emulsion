import EmulsionKit
import EmulsionUI
import SwiftUI

/// The expanded library's inspector: the previewed photo as large as the pane allows, with
/// when it was taken, what kind of file it is, and the way into the editor.
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
                PreviewCaption(photo: photo) { edit(photoID) }
            }
            .padding(FilmLabLayout.inset)
        }
    }
}

private struct PreviewCaption: View {
    let photo: PhotoRecord
    let edit: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FilmLabLayout.gap) {
                details
                Spacer(minLength: FilmLabLayout.gap)
                editButton
            }
            VStack(alignment: .leading, spacing: FilmLabLayout.gap) {
                details
                editButton
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading) {
            Text(photo.created, format: .dateTime.day().month(.wide).year())
                .font(.headline)
            if !facts.isEmpty {
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var editButton: some View {
        Button("Edit Photo", systemImage: "dial.low", action: edit)
            .buttonStyle(.glass)
            .controlSize(.large)
    }

    private var facts: String {
        [
            photo.isRAW ? String(localized: "RAW") : nil,
            photo.isEdited ? String(localized: "Edited") : nil,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}
