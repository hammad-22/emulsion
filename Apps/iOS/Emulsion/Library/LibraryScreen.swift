import EmulsionKit
import EmulsionUI
import SwiftUI

/// The photo library: every imported photo with its film look, newest first.
/// The camera (MOV-60) will open in front of this.
struct LibraryScreen: View {
    @Environment(PhotoStore.self) private var store
    @State private var path: [PhotoRecord.ID] = []
    @State private var selection = LibrarySelection()
    @State private var previewID: PhotoRecord.ID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var importError: String?
    @Namespace private var editorTransition
    /// An even column count for the grid beside the preview (HIG, iPhone Duo inner display).
    private let expandedColumnCount = 4

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.photos.isEmpty {
                    LibraryEmptyState(error: $importError)
                } else {
                    libraryContent
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

    private var libraryContent: some View {
        GeometryReader { geometry in
            if #available(iOS 27.1, *), geometry.isExpandedCanvas(horizontalSizeClass: horizontalSizeClass) {
                expandedLibrary
            } else {
                PhotoGrid(selection: $selection, transition: editorTransition, edit: openEditor) { id in
                    previewID = id
                    openEditor(id)
                }
            }
        }
    }

    @available(iOS 27.1, *)
    private var expandedLibrary: some View {
        ArrangementView {
            PhotoGrid(
                selection: $selection, transition: editorTransition, columnCount: expandedColumnCount,
                previewID: shownPreviewID, edit: openEditor
            ) {
                previewID = $0
            }
        } secondary: {
            UnobscuredContent {
                LibraryPreview(photoID: shownPreviewID, edit: openEditor)
            }
        }
        .arrangementViewStyle(.split)
    }

    private func openEditor(_ id: PhotoRecord.ID) { path.append(id) }

    /// The photo picked for preview while it still exists, otherwise the newest.
    private var shownPreviewID: PhotoRecord.ID? {
        if let previewID, store.photo(previewID) != nil { return previewID }
        return store.photos.first?.id
    }

    private var photoCount: Text {
        store.photos.isEmpty ? Text("") : Text("^[\(store.photos.count) photo](inflect: true)")
    }
}
