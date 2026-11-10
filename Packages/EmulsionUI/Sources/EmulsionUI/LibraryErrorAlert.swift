import EmulsionKit
import SwiftUI

extension View {
    /// Shows the library's `lastError` (an index that couldn't be read, or an edit or
    /// delete that couldn't be saved) as an alert, and clears it when dismissed.
    public func libraryErrorAlert(_ store: PhotoStore) -> some View {
        modifier(LibraryErrorAlert(store: store))
    }
}

private struct LibraryErrorAlert: ViewModifier {
    @Bindable var store: PhotoStore

    func body(content: Content) -> some View {
        content.alert(
            store.lastError?.localizedDescription ?? "", isPresented: Binding(isPresenting: $store.lastError)
        ) {}
    }
}
