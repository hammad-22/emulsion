import EmulsionKit
import EmulsionUI
import SwiftUI

/// Select at the top; at the bottom, within reach of a thumb, Import, or while selecting,
/// Delete.
struct LibraryToolbar: ToolbarContent {
    @Binding var selection: LibrarySelection
    let onImportError: (any Error) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if selection.isActive {
                Button("Done") { selection = LibrarySelection() }
            } else {
                Button("Select") { selection.isActive = true }
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            if selection.isActive {
                Button("Delete", systemImage: "trash", role: .destructive) { selection.pendingDeletion = selection.photos }
                    .disabled(selection.photos.isEmpty)
            } else {
                PhotoImportButton(onError: onImportError)
            }
        }
    }
}
