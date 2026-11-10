import EmulsionKit
import EmulsionUI
import SwiftUI

@main
struct EmulsionApp: App {
    @State private var store = PhotoStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .libraryErrorAlert(store)
                .environment(store)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
