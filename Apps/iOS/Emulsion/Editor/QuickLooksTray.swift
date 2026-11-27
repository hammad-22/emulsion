import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct QuickLooksTray: View {
    let session: EditSession
    let isVertical: Bool
    @Environment(RecipeStore.self) private var store
    @ScaledMetric private var preferredSwatchWidth = 92.0

    private var swatchWidth: CGFloat { min(preferredSwatchWidth, 128) }
    private var verticalTrayWidth: CGFloat { swatchWidth + FilmLabLayout.compact }

    var body: some View {
        swatches
            .frame(width: isVertical ? verticalTrayWidth : nil)
            .padding(FilmLabLayout.compact)
            .glassEffect(.regular, in: .rect(cornerRadius: FilmLabLayout.panelCorner))
    }

    @ViewBuilder private var swatches: some View {
        if isVertical {
            ScrollView {
                LazyVStack(spacing: FilmLabLayout.compact) { recipeSections }
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: FilmLabLayout.compact) { recipeSections }
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var recipeSections: some View {
        options(CuratedLooks.recipes)
        options(store.recipes)
    }

    @ViewBuilder private func options(_ recipes: [Recipe]) -> some View {
        ForEach(recipes) { recipe in
            let isSelected = recipe.matches(session.adjustments)
            Button {
                session.apply(recipe)
            } label: {
                VStack(spacing: FilmLabLayout.hairline) {
                    LookSwatch(url: session.url, adjustments: recipe.applying(to: session.adjustments))
                        .frame(width: swatchWidth, height: swatchWidth)
                        .clipShape(.rect(cornerRadius: FilmLabLayout.gap))
                        .overlay(alignment: .bottomTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.8))
                                    .padding(FilmLabLayout.hairline)
                            }
                        }
                    Text(recipe.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: swatchWidth)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recipe.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
