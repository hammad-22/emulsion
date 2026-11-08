import EmulsionKit
import PhotosUI
import SwiftUI

/// Picks photos from the system library and adds their original files to the store.
/// Reports the first failure through `onError`; the rest of the batch still imports.
public struct PhotoImportButton: View {
    @Environment(PhotoStore.self) private var store
    @State private var selection: [PhotosPickerItem] = []
    private let onError: (any Error) -> Void

    public init(onError: @escaping (any Error) -> Void) {
        self.onError = onError
    }

    public var body: some View {
        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) {
            Label("Import", systemImage: "plus")
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            selection = []
            Task { await importPhotos(items) }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var firstError: (any Error)?
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                try store.add(data)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { onError(firstError) }
    }
}
