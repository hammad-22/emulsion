import CoreImage
import EmulsionFixtures
import Foundation

@testable import EmulsionKit

/// A small JPEG of the color-patch fixture.
enum TestPhoto {
    static let jpeg: Data = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // A fixture that fails to encode is a broken test setup, not a test failure.
        return CIContext().jpegRepresentation(of: SceneFixtures.patches(), colorSpace: space)!
    }()
}

/// A throwaway library: its own folder and render service, removed when the test ends,
/// so tests can run in parallel.
@MainActor
final class TestLibrary {
    let folder = URL.temporaryDirectory.appending(path: "EmulsionKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let renderService = RenderService()
    lazy var store = PhotoStore(folder: folder, renderService: renderService)
    var indexURL: URL { folder.appending(path: "library.json") }

    /// The same folder opened again, as on the next launch.
    func reopened() -> PhotoStore { PhotoStore(folder: folder, renderService: RenderService()) }

    isolated deinit { try? FileManager.default.removeItem(at: folder) }
}
