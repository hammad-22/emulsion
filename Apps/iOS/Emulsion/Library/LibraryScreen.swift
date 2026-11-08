import EmulsionKit
import EmulsionUI
import SwiftUI

/// The photo library: every imported photo with its film look, newest first.
/// The camera (MOV-60) will open in front of this.
struct LibraryScreen: View {
    @Environment(PhotoStore.self) private var store
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.photos.isEmpty {
                    emptyState
                } else {
                    PhotoGrid()
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: PhotoRecord.ID.self) { EditorScreen(photoID: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { importButton }
            }
            .alert("Couldn't import", isPresented: Binding(isPresenting: $importError), presenting: importError) { _ in
            } message: {
                Text($0)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Photos Yet", systemImage: "film")
        } description: {
            Text("Import a photo, or try a sample, to develop it as a film negative and print.")
        } actions: {
            importButton.buttonStyle(.glass)
            Button("Try Sample Photos", systemImage: "photo.stack") {
                do {
                    try store.addSamples()
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private var importButton: some View {
        PhotoImportButton { importError = $0.localizedDescription }
    }
}
