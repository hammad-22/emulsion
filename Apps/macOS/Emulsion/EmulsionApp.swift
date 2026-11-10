import EmulsionKit
import SwiftUI

@main
struct EmulsionApp: App {
    @State private var store = PhotoStore()

    // Room for the library, photo and adjustment panel at launch.
    private let initialSize = CGSize(width: 1100, height: 700)

    var body: some Scene {
        Window("Emulsion", id: "library") {
            LibraryScreen()
                .environment(store)
        }
        .defaultSize(width: initialSize.width, height: initialSize.height)
    }
}
