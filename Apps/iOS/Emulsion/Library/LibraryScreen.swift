import EmulsionKit
import EmulsionUI
import SwiftUI

/// The photo library: every imported photo with its film look, newest first.
/// The camera (MOV-60) will open in front of this.
struct LibraryScreen: View {
    @Environment(PhotoStore.self) private var store
    @State private var importError: String?
    @Namespace private var editorTransition

    var body: some View {
        NavigationStack {
            Group {
                if store.photos.isEmpty {
                    LibraryEmptyState(error: $importError)
                } else {
                    PhotoGrid(transition: editorTransition)
                }
            }
            .navigationTitle("Library")
            .navigationSubtitle(store.photos.isEmpty ? Text("") : Text("^[\(store.photos.count) photo](inflect: true)"))
            .navigationDestination(for: PhotoRecord.ID.self) { id in
                EditorScreen(photoID: id)
                    .navigationTransition(.zoom(sourceID: id, in: editorTransition))
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PhotoImportButton { importError = $0.localizedDescription }
                }
            }
            .alert("Couldn't import", isPresented: Binding(isPresenting: $importError), presenting: importError) { _ in
            } message: {
                Text($0)
            }
        }
    }
}
