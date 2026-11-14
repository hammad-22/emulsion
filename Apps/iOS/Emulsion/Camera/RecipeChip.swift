import EmulsionCore
import EmulsionUI
import SwiftUI

/// The selected chip is filled, bold and checked, so the choice doesn't rely on color.
struct RecipeChip: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void

    private let horizontalPadding: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: FilmLabLayout.hairline) {
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(recipe.name)
                    .font(isSelected ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: FilmLabLayout.minimumControlHeight)
            .background(.white.opacity(isSelected ? FilmLabLayout.selectedFill : 0), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(recipe.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // The strip stops growing at the first accessibility size; a long press shows the name large.
        .accessibilityShowsLargeContentViewer { Text(recipe.name) }
    }
}
