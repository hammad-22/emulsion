import EmulsionCore
import EmulsionKit
import SwiftUI
import UniformTypeIdentifiers

struct LooksPicker: View {
    let session: EditSession
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isImporting = false
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var deleting: Recipe?
    // Keeps the Mac sheet usable at its smallest size.
    private let minimumSheetSize = CGSize(width: 300, height: 320)

    var body: some View {
        NavigationStack {
            collection
                .navigationTitle("Looks")
                .toolbar { toolbar }
                .alert("Save Look", isPresented: $isSaving) {
                    TextField("Name", text: $name)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { perform { try store.save(name: name, adjustments: session.adjustments) } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } message: {
                    Text("Save these adjustments to use on another photo. Each photo keeps its own grain pattern.")
                }
                .alert("Couldn't Complete Action", isPresented: Binding(isPresenting: $errorMessage)) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                .confirmationDialog(
                    "Delete this saved look?", isPresented: Binding(isPresenting: $deleting), titleVisibility: .visible,
                    presenting: deleting
                ) { recipe in
                    Button("Delete Look", role: .destructive) {
                        perform { try store.delete(recipe) }
                    }
                } message: { _ in
                    Text("Photos already using these adjustments keep their edits.")
                }
                .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    perform {
                        if let url = try result.get().first { try store.importRecipe(at: url) }
                    }
                }
        }
        .tint(.primary)
        .frame(minWidth: minimumSheetSize.width, minHeight: minimumSheetSize.height)
    }

    private var collection: some View {
        ScrollViewReader { proxy in
            lookList
                .onChange(of: store.recipes.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var lookList: some View {
        List {
            Section {
                sectionTitle("Emulsion")
                ForEach(CuratedLooks.recipes) { recipe in row(recipe) }
            } footer: {
                Text(
                    "Artistic looks made with Emulsion's current film model. Applying a look replaces the adjustment values and keeps your original photo."
                )
            }
            Section {
                sectionTitle("Your Looks")
                if store.recipes.isEmpty {
                    Text("Save your current edit as a look, or import one to make it yours.")
                        .foregroundStyle(Color.primary)
                }
                ForEach(store.recipes) { recipe in row(recipe, canDelete: true) }
            }
            if let loadError = store.loadError {
                Section { Text(loadError.localizedDescription).foregroundStyle(Color.primary) }
            }
        }
        .accessibilityIdentifier("looks-collection")
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .bold()
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Import Look", systemImage: "square.and.arrow.down") { isImporting = true }
                .disabled(store.loadError != nil)
            Button("Save Look", systemImage: "plus") {
                name = ""
                isSaving = true
            }
            .disabled(store.loadError != nil)
        }
    }

    private func row(_ recipe: Recipe, canDelete: Bool = false) -> some View {
        RecipeRow(recipe: recipe, isApplied: recipe.matches(session.adjustments), canDelete: canDelete) {
            session.apply(recipe)
            dismiss()
        } delete: {
            deleting = recipe
        }
    }

    private func perform<T>(_ action: () throws -> T) {
        do { _ = try action() } catch { errorMessage = error.localizedDescription }
    }
}
