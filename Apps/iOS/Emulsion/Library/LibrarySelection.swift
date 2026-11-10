import EmulsionKit
import SwiftUI

/// Which photos are picked while the library is in Select mode, and which are waiting for
/// the user to confirm deleting them.
struct LibrarySelection: Equatable {
    var isActive = false
    var photos: Set<PhotoRecord.ID> = []
    var pendingDeletion: Set<PhotoRecord.ID> = []

    var title: Text {
        photos.isEmpty ? Text("Select Photos") : Text("\(photos.count) Selected")
    }

    mutating func toggle(_ id: PhotoRecord.ID) {
        if photos.remove(id) == nil { photos.insert(id) }
    }

    /// Starts selecting with one photo already picked (from a thumbnail's menu).
    mutating func begin(with id: PhotoRecord.ID) {
        isActive = true
        photos = [id]
    }
}

extension View {
    /// Asks before deleting the photos in `pending`, then hands them to `delete`.
    func deletionConfirmation(
        _ pending: Binding<Set<PhotoRecord.ID>>, delete: @escaping (Set<PhotoRecord.ID>) -> Void
    ) -> some View {
        let count = pending.wrappedValue.count
        let title = count == 1 ? Text("Delete this photo?") : Text("Delete \(count) photos?")
        return confirmationDialog(
            title,
            isPresented: Binding(get: { !pending.wrappedValue.isEmpty }, set: { if !$0 { pending.wrappedValue = [] } }),
            titleVisibility: .visible
        ) {
            Button("^[Delete \(count) Photo](inflect: true)", role: .destructive) { delete(pending.wrappedValue) }
        } message: {
            Text("The original files and their edits are removed from Emulsion.")
        }
    }
}
