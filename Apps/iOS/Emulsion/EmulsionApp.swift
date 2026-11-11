import EmulsionKit
import EmulsionUI
import SwiftUI

@main
struct EmulsionApp: App {
    @State private var store = PhotoStore()
    @State private var recipes = RecipeStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            content
                .libraryErrorAlert(store)
                .environment(store)
                .environment(recipes)
                .environment(settings)
        }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--component-gallery") {
                ComponentGallery()
            } else {
                LibraryScreen()
            }
        #else
            LibraryScreen()
        #endif
    }
}
