import EmulsionKit
import EmulsionUI
import SwiftUI

struct PreviewCaption: View {
    let photo: PhotoRecord
    let canEdit: Bool
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
            .disabled(!canEdit)
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
