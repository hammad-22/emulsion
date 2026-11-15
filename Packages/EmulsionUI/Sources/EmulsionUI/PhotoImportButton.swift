import EmulsionCore
import EmulsionKit
import PhotosUI
import SwiftUI

/// Imports the picked photos' originals; reports the first failure while the rest still import.
public struct PhotoImportButton: View {
    @Environment(PhotoStore.self) private var store
    @State private var selection: [PhotosPickerItem] = []
    @State private var isPicking = false
    private let fillsWidth: Bool
    private let onError: (any Error) -> Void

    public init(fillsWidth: Bool = false, onError: @escaping (any Error) -> Void) {
        self.fillsWidth = fillsWidth
        self.onError = onError
    }

    public var body: some View {
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
            // Unstructured, so the batch survives its first photo replacing the empty state.
            Task { await importPhotos(items) }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var firstError: (any Error)?
        for item in items {
            do {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else { throw EmulsionError.unsupportedPhoto }
                try await store.add(data)
            } catch is CancellationError {
                break
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { onError(firstError) }
    }
}
