import EmulsionKit
import PhotosUI
import SwiftUI

/// Picks photos from the system library and adds their original files to the store.
/// Reports the first failure through `onError`; the rest of the batch still imports.
public struct PhotoImportButton: View {
    @Environment(PhotoStore.self) private var store
    @State private var selection: [PhotosPickerItem] = []
    @State private var isPicking = false
    private let fillsWidth: Bool
    private let onError: (any Error) -> Void

    /// `fillsWidth` stretches the label, for a button stacked with others of equal width.
    public init(fillsWidth: Bool = false, onError: @escaping (any Error) -> Void) {
        self.fillsWidth = fillsWidth
        self.onError = onError
    }

    public var body: some View {
        // A plain button presenting the picker, so button and label styles apply as usual.
        Button {
            isPicking = true
        } label: {
            Label("Import", systemImage: "plus")
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .photosPicker(isPresented: $isPicking, selection: $selection, matching: .images, preferredItemEncoding: .current)
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
