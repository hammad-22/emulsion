import EmulsionKit
import EmulsionUI
import SwiftUI

@main
struct EmulsionApp: App {
    @State private var store = PhotoStore()
    @State private var recipes = RecipeStore()

    // Room for the library, photo and adjustment panel at launch.
    private let initialSize = CGSize(width: 1100, height: 700)

    var body: some Scene {
        Window("Emulsion", id: "library") {
            LibraryScreen()
                .libraryErrorAlert(store)
                .environment(store)
                .environment(recipes)
        }
        .defaultSize(width: initialSize.width, height: initialSize.height)
    }
}
