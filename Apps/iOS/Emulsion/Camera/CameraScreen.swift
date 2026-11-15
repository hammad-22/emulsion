import EmulsionKit
import EmulsionUI
import SwiftUI

struct CameraScreen: View {
    @Environment(PhotoStore.self) private var store
    @Environment(AppSettings.self) private var settings
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
        // Presenting from here while the library covers the camera would dismiss the cover.
        .background {
            if !showsLibrary { Color.clear.libraryErrorAlert(store) }
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .task {
            guard model == nil else { return }
            let camera = CameraModel(source: Self.makeSource(), store: store, settings: settings)
            #if DEBUG
                camera.recordsViewfinderTiming = ViewfinderTimingOverlay.isEnabled
            #endif
            model = camera
        }
        .task(id: isLive) {
            if isLive { await model?.start() } else { await model?.stop() }
        }
        .fullScreenCover(isPresented: $showsLibrary) {
            LibraryScreen()
                .libraryErrorAlert(store)
                .navigationTransition(.zoom(sourceID: LibraryButton.transitionID, in: libraryTransition))
        }
    }

    private var isLive: Bool { model != nil && scenePhase == .active && !showsLibrary }

    private static func makeSource() -> any CameraSource {
        #if targetEnvironment(simulator)
            #if DEBUG
                if let scenario = CameraScenario.launched { return scenario.makeSource() }
            #endif
            return MockCameraSource()
        #else
            AVCameraSource()
        #endif
    }
}
