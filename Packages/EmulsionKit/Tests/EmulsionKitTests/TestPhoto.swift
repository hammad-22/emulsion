import CoreImage
import EmulsionFixtures
import Foundation

/// A small JPEG of the color-patch fixture, and a throwaway library folder per test.
enum TestPhoto {
    static let jpeg: Data = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // A fixture that fails to encode is a broken test setup, not a test failure.
        return CIContext().jpegRepresentation(of: SceneFixtures.patches(), colorSpace: space)!
    }()

    static func temporaryFolder() -> URL {
        URL.temporaryDirectory.appendingPathComponent("EmulsionKitTests-\(UUID().uuidString)", isDirectory: true)
    }
}
