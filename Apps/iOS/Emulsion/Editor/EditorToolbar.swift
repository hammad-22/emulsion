import EmulsionKit
import EmulsionUI
import SwiftUI

/// Compare, save to Photos, reset, and delete for the photo being edited.
struct EditorToolbar: ToolbarContent {
    let session: EditSession
    @Binding var isShowingOriginal: Bool

    @Environment(PhotoStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var message: String?
    @State private var isConfirmingDelete = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle("Compare", systemImage: "square.split.2x1", isOn: $isShowingOriginal)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                Task { await export() }
            }
            .disabled(isExporting)
            .alert(message ?? "", isPresented: Binding(isPresenting: $message)) {}
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Reset Edits", systemImage: "arrow.counterclockwise") { session.reset() }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete) {
                    Button("Delete Photo", role: .destructive) {
                        Task {
                            await store.delete(session.photo.id)
                            dismiss()
                        }
                    }
                } message: {
                    Text("The original file and its edits are removed from Emulsion.")
                }
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            try await session.saveToPhotos(format: settings.format)
            message = "Saved to Photos"
        } catch {
            message = error.localizedDescription
        }
    }
}
