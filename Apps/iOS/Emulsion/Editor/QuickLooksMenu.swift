import EmulsionCore
import EmulsionKit
import SwiftUI

struct QuickLooksMenu: View {
    let session: EditSession

    @Environment(RecipeStore.self) private var store
    @State private var pendingRecipe: Recipe?

    var body: some View {
        Menu {
            Section("Film and Digicam") { choices(CuratedLooks.recipes) }
            if !store.recipes.isEmpty {
                Section("Saved Looks") { choices(store.recipes) }
            }
        } label: {
            Label("Quick Looks", systemImage: "film")
        }
        .alert(
            "Replace current adjustments?",
            isPresented: Binding(isPresenting: $pendingRecipe),
            presenting: pendingRecipe
        ) { recipe in
            Button("Apply \(recipe.name)") { session.apply(recipe) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Applying a look replaces the adjustments on this photo.")
        }
    }

    private func choices(_ recipes: [Recipe]) -> some View {
        ForEach(recipes) { recipe in
            let isSelected = recipe.matches(session.adjustments)
            Button {
                guard !isSelected else { return }
                if session.isEdited {
                    pendingRecipe = recipe
                } else {
                    session.apply(recipe)
                }
            } label: {
                if isSelected {
                    Label(recipe.name, systemImage: "checkmark")
                } else {
                    Text(recipe.name)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
