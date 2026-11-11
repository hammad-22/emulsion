import CoreImage
import EmulsionCore
import EmulsionFixtures
import Foundation

@testable import EmulsionKit

/// A small JPEG of the color-patch fixture.
enum TestPhoto {
    static let jpeg: Data = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Encoded on the CPU so the tests' only GPU context is the shared renderer's (MOV-127).
        // A fixture that fails to encode is a broken test setup, not a test failure.
        return CIContext(options: [.useSoftwareRenderer: true])
            .jpegRepresentation(of: SceneFixtures.patches(), colorSpace: space)!
    }()
}

/// A throwaway library: its own folder and render service, removed when the test ends,
/// so tests can run in parallel.
@MainActor
final class TestLibrary {
    /// One renderer (GPU context and kernels) for every test's service, as the app has one.
    /// MOV-127: both CI crashes came as parallel tests each started their own context.
    /// `Renderer` holds only immutable state and a `CIContext`, which is thread-safe.
    /// Nil if the kernels fail to load; each service then reports that itself.
    private static let renderer = try? Renderer()

    let folder = URL.temporaryDirectory.appending(path: "EmulsionKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let renderService = RenderService(renderer: TestLibrary.renderer, thumbnails: ThumbnailCache(purgesUnderMemoryPressure: false))
    lazy var store = PhotoStore(folder: folder, renderService: renderService)

    /// The same folder opened again, as on the next launch.
    func reopened() -> PhotoStore {
        PhotoStore(
            folder: folder,
            renderService: RenderService(renderer: TestLibrary.renderer, thumbnails: ThumbnailCache(purgesUnderMemoryPressure: false)))
    }

    isolated deinit { try? FileManager.default.removeItem(at: folder) }
}
