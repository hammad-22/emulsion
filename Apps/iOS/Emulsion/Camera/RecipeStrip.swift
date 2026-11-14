import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct RecipeStrip: View {
    let recipes: [Recipe]
    let selection: Recipe
    let select: (Recipe) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
        .dynamicTypeSize(...FilmLabLayout.largestCameraTextSize)
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
