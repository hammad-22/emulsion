import EmulsionKit
import SwiftUI

public struct LooksButton: View {
    private let session: EditSession
    @State private var isPresented = false

    public init(session: EditSession) { self.session = session }

    public var body: some View {
        Button("Looks", systemImage: "camera.filters") { isPresented = true }
            .sheet(isPresented: $isPresented) {
                LooksPicker(session: session)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}
