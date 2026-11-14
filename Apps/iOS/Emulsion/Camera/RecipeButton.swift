import EmulsionCore
import EmulsionKit
import SwiftUI

struct RecipeButton: View {
    let recipe: Recipe
    let isShowingRecipes: Bool
    let toggle: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Match the glass button's padding and, with it, the library button's height.
    private static let labelPadding: CGFloat = 12
    private static let labelHeight: CGFloat = 44
    private static let symbol = "camera.filters"
    private static let symbolToNameSpacing: CGFloat = 2
    private static let nameMinimumScale = 0.7

    var body: some View {
        if let toggle {
            Button(action: toggle) { label }
                .buttonStyle(.glass)
                .accessibilityLabel("Recipe")
                .accessibilityValue(recipe.name)
                .accessibilityHint(isShowingRecipes ? "Hides the recipes" : "Shows the recipes")
                .accessibilityShowsLargeContentViewer { Label(recipe.name, systemImage: Self.symbol) }
        } else {
            label
                .padding(.horizontal, Self.labelPadding)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recipe")
                .accessibilityValue(recipe.name)
        }
    }

    private var label: some View {
        VStack(spacing: Self.symbolToNameSpacing) {
            Image(systemName: Self.symbol)
                .font(.body.weight(.semibold))
                .symbolVariant(isShowingRecipes ? .fill : .none)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(recipe.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.nameMinimumScale)
            }
        }
        .frame(width: LibraryButton.size, height: Self.labelHeight)
    }
}
