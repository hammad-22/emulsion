import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// The recipes as a row of glass chips. The selected one is filled, bold and checked, so the
/// choice doesn't rely on color. Where the chips don't all fit, the row scrolls, and the
/// selection scrolls into view when it changes or the strip appears.
struct RecipeStrip: View {
    /// In order: Emulsion's curated looks, then the user's saved ones.
    let recipes: [Recipe]
    /// A snapshot: a recipe since deleted from the saved looks simply has no chip selected.
    let selection: Recipe
    let select: (Recipe) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Centred when every chip fits (iPhone Duo unfolded); scrolling otherwise.
        ViewThatFits(in: .horizontal) {
            chips
            ScrollViewReader { proxy in
                ScrollView(.horizontal) { chips }
                    .scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(selection.id, anchor: .center) }
                    .onChange(of: selection.id) { _, id in
                        withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: selection.id)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recipes")
    }

    private var chips: some View {
        GlassEffectContainer(spacing: FilmLabLayout.compact) {
            HStack(spacing: FilmLabLayout.compact) {
                ForEach(recipes) { recipe in
                    RecipeChip(recipe: recipe, isSelected: recipe.id == selection.id) { select(recipe) }
                        .id(recipe.id)
                }
            }
            .padding(.horizontal, FilmLabLayout.compact)
        }
    }
}

private struct RecipeChip: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FilmLabLayout.hairline) {
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(recipe.name)
                    .font(isSelected ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
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
