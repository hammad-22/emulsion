import EmulsionKit
import EmulsionUI
import SwiftUI

/// The photo library: every imported photo with its film look, newest first.
/// The camera (MOV-60) will open in front of this.
struct LibraryScreen: View {
    @Environment(PhotoStore.self) private var store
    @State private var path: [PhotoRecord.ID] = []
    @State private var selection = LibrarySelection()
    @State private var importError: String?
    @Namespace private var editorTransition

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.photos.isEmpty {
                    LibraryEmptyState(error: $importError)
                } else {
                    PhotoGrid(selection: $selection, transition: editorTransition) { path.append($0) }
                }
            }
            .navigationTitle(selection.isActive ? selection.title : Text("Library"))
            .navigationSubtitle(photoCount)
            .navigationDestination(for: PhotoRecord.ID.self) { id in
                EditorScreen(photoID: id)
                    .navigationTransition(.zoom(sourceID: id, in: editorTransition))
            }
            .toolbar {
                if !store.photos.isEmpty {
                    LibraryToolbar(selection: $selection) { importError = $0.localizedDescription }
                }
            }
            .deletionConfirmation($selection.pendingDeletion) { ids in
                selection = LibrarySelection()
                Task { await store.delete(ids) }
            }
            .alert("Couldn't import", isPresented: Binding(isPresenting: $importError), presenting: importError) { _ in
            } message: {
                Text($0)
            }
            .onChange(of: store.photos.isEmpty) { _, isEmpty in
                if isEmpty { selection = LibrarySelection() }
            }
        }
    }

    private var photoCount: Text {
        store.photos.isEmpty ? Text("") : Text("^[\(store.photos.count) photo](inflect: true)")
    }
}
