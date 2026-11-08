import EmulsionKit
import EmulsionUI
import SwiftUI

struct LibraryScreen: View {
    @Environment(PhotoStore.self) private var store
    @State private var selection: PhotoRecord.ID?
    @State private var importError: String?
    // Large enough to tell bundled and imported photos apart in the sidebar.
    private let thumbnailSize: CGFloat = 56
    // Keep the date and a recognizable thumbnail visible together.
    private let sidebarWidth: CGFloat = 220

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Array(store.photos.enumerated()), id: \.element.id) { index, photo in
                    HStack {
                        RenderedPhoto(url: store.url(for: photo), adjustments: photo.adjustments, contentMode: .fill)
                            .frame(width: thumbnailSize, height: thumbnailSize)
                        Text(photo.created, format: .dateTime.day().month().year().hour().minute())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Photo \(index + 1), \(photo.created, format: .dateTime.day().month().year())"))
                    .tag(photo.id)
                }
            }
            .navigationSplitViewColumnWidth(ideal: sidebarWidth)
            .navigationTitle("Library")
            .overlay {
                if store.photos.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: "film")
                    } actions: {
                        Button("Try Sample Photos") { addSamples() }
                    }
                }
            }
            .toolbar {
                PhotoImportButton { importError = $0.localizedDescription }
            }
        } detail: {
            if let selection, let photo = store.photo(selection) {
                PhotoEditor(photo: photo, store: store)
                    .id(photo.id)
            } else {
                ContentUnavailableView("Select a Photo", systemImage: "photo")
            }
        }
        .alert("Couldn't import", isPresented: Binding(isPresenting: $importError), presenting: importError) { _ in
        } message: {
            Text($0)
        }
    }

    private func addSamples() {
        do {
            try store.addSamples()
            selection = store.photos.first?.id
        } catch {
            importError = error.localizedDescription
        }
    }
}
