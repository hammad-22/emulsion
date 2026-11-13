import EmulsionKit
import SwiftUI

/// The same saved-look collection and application flow in both editors.
public struct LooksButton: View {
    private let session: EditSession
    @State private var isPresented = false

    public init(session: EditSession) { self.session = session }

    public var body: some View {
        Button("Looks", systemImage: "camera.filters") { isPresented = true }
            .sheet(isPresented: $isPresented) {
                LooksPicker(session: session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }
}
