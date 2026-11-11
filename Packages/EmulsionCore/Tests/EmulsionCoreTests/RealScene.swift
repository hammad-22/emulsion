import CoreImage
import Foundation

/// Real photographs frozen as developed, downscaled scene-linear half-float TIFFs in `Scenes/` (CC0 only;
/// see `Scenes/PROVENANCE.md`). Freezing keeps the look suite independent of the OS RAW decoder
/// and of develop work in flight; `Developer.develop` itself is covered by the local tier.
enum RealScene: String, CaseIterable, Sendable {
    case iphone12ProRAW = "iphone12pro-proraw"
    case pixel8ProDNG = "pixel8pro-dng"

    /// Original file name in the source folder.
    var sourceName: String {
        switch self {
        case .iphone12ProRAW: "iPhone12Pro_ProRAW_CC0.DNG"
        case .pixel8ProDNG: "Pixel8Pro_CC0.dng"
        }
    }

    static let developDimension: CGFloat = 960
    static let frozenLongEdge: CGFloat = 240

    /// Each scene is decoded once per process, on first use; CIImage is immutable.
    private static let iphone12ProRAWImage = Result { try RealScene.iphone12ProRAW.decode() }
    private static let pixel8ProDNGImage = Result { try RealScene.pixel8ProDNG.decode() }

    func image() throws -> CIImage {
        switch self {
        case .iphone12ProRAW: try Self.iphone12ProRAWImage.get()
        case .pixel8ProDNG: try Self.pixel8ProDNGImage.get()
        }
    }

    private func decode() throws -> CIImage {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "tiff", subdirectory: "Scenes") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Scenes/\(rawValue).tiff"])
        }
        return try SceneFile.image(contentsOf: url)
    }
}
