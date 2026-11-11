import EmulsionKit
import EmulsionUI
import SwiftUI

/// Compare and Reset together, Save to Photos as the one prominent action, and Delete
/// under More.
struct EditorToolbar: ToolbarContent {
    let session: EditSession
    @Binding var isComparing: Bool
    @Binding var showsAdjustments: Bool

    @Environment(PhotoStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportResult: ExportResult?
    @State private var isConfirmingDelete = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                showsAdjustments.toggle()
            } label: {
                Label(showsAdjustments ? "Hide Adjustments" : "Adjust", systemImage: "dial.low")
            }
            .labelStyle(.titleAndIcon)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Neutral like the rest of the editor: no accent color beside the photograph.
            Toggle("Compare", systemImage: "square.split.2x1", isOn: $isComparing)
                .tint(.white)
            Button("Reset Edits", systemImage: "arrow.counterclockwise") { session.reset() }
                .disabled(!session.isEdited)
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                Task { await export() }
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(isExporting)
            .alert(exportResult?.message ?? "", isPresented: Binding(isPresenting: $exportResult)) {}
            .sensoryFeedback(trigger: exportResult) { _, result in result?.feedback }
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
            exportResult = .saved
        } catch {
            exportResult = .failed(error.localizedDescription)
        }
    }
}

private enum ExportResult: Equatable {
    case saved
    case failed(String)

    var message: String {
        switch self {
        case .saved: String(localized: "Saved to Photos")
        case .failed(let message): message
        }
    }

    var feedback: SensoryFeedback {
        switch self {
        case .saved: .success
        case .failed: .error
        }
    }
}
