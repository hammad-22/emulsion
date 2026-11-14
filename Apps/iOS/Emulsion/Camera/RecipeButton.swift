import EmulsionCore
import EmulsionKit
import SwiftUI

/// Toggles the recipe strip; where the strip is always visible (`toggle` is nil) it only names the recipe.
struct RecipeButton: View {
    let recipe: Recipe
    let isShowingRecipes: Bool
    let toggle: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Matches the glass button style's own horizontal padding.
    private static let labelPadding: CGFloat = 12
    /// With the glass button's vertical padding, about the library button's height.
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
            // Doesn't fit the fixed width at accessibility sizes; the large content viewer shows it.
            if !dynamicTypeSize.isAccessibilitySize {
                Text(recipe.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.nameMinimumScale)
            }
        }
        // A fixed width, so switching recipes never moves the button.
        .frame(width: LibraryButton.size, height: Self.labelHeight)
    }
}
