import EmulsionKit
import SwiftUI

@main
struct EmulsionApp: App {
    @State private var store = PhotoStore()
    @State private var camera = CameraModel()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .environment(store)
                .environment(camera)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
