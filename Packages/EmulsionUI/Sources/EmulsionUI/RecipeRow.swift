import EmulsionCore
import EmulsionKit
import SwiftUI

struct RecipeRow: View {
    let recipe: Recipe
    let isApplied: Bool
    let canDelete: Bool
    let apply: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            Button(action: apply) {
                HStack(spacing: FilmLabLayout.gap) {
                    VStack(alignment: .leading, spacing: FilmLabLayout.hairline) {
                        Text(recipe.name).font(.headline)
                        if !recipe.summary.isEmpty { Text(recipe.summary).font(.subheadline).foregroundStyle(Color.primary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isApplied { Image(systemName: "checkmark").accessibilityLabel("Applied") }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Apply look and return to your photo")
            Menu {
                ShareLink(item: RecipeTransfer(recipe: recipe), preview: SharePreview(recipe.name)) {
                    Label("Share Look", systemImage: "square.and.arrow.up")
                }
                if canDelete { Button("Delete Look", systemImage: "trash", role: .destructive, action: delete) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: FilmLabLayout.minimumControlHeight, minHeight: FilmLabLayout.minimumControlHeight)
            }
            .accessibilityLabel(Text("Options for \(recipe.name)"))
        }
        .padding(.vertical, FilmLabLayout.hairline)
    }
}
