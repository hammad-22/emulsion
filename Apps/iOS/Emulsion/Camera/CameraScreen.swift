import EmulsionKit
import EmulsionUI
import SwiftUI

/// The app opens on the camera: a live RAW viewfinder, with the library one tap away.
/// The camera runs only while this screen is in front and the app is active.
struct CameraScreen: View {
    @Environment(PhotoStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CameraModel?
    @State private var showsLibrary = false
    @Namespace private var libraryTransition

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                CameraContent(model: model, showsLibrary: $showsLibrary, transition: libraryTransition)
            }
        }
        // A neutral dark surround keeps the picture central, as in the editor. Set on this
        // screen only, so the library above it keeps the system appearance.
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .task {
            if model == nil { model = CameraModel(source: Self.makeSource(), store: store) }
        }
        .task(id: isLive) {
            if isLive { await model?.start() } else { await model?.stop() }
        }
        .fullScreenCover(isPresented: $showsLibrary) {
            LibraryScreen()
                .navigationTransition(.zoom(sourceID: LibraryButton.transitionID, in: libraryTransition))
        }
    }

    private var isLive: Bool { model != nil && scenePhase == .active && !showsLibrary }

    /// The Simulator has no camera, so it shows the sample photos as a live viewfinder.
    private static func makeSource() -> any CameraSource {
        #if targetEnvironment(simulator)
            MockCameraSource()
        #else
            AVCameraSource()
        #endif
    }
}
