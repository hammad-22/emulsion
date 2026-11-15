import EmulsionKit
import SwiftUI

extension View {
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
