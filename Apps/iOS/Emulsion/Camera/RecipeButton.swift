import EmulsionCore
import EmulsionKit
import SwiftUI

struct RecipeButton: View {
    let recipe: Recipe
    let isShowingRecipes: Bool
    let toggle: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let symbol = "camera.filters"

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
                .padding(.horizontal, Layout.labelPadding)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recipe")
                .accessibilityValue(recipe.name)
        }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Image(systemName: Self.symbol)
                .font(.body.weight(.semibold))
                .symbolVariant(isShowingRecipes ? .fill : .none)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(recipe.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: LibraryButton.size, height: Layout.labelHeight)
    }

    // Match the glass button's padding and, with it, the library button's height.
    private enum Layout {
        static let labelPadding: CGFloat = 12
        static let labelHeight: CGFloat = 44
    }
}
