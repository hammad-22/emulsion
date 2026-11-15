import CoreImage
import Foundation

/// Real photographs frozen as developed (CC0 only, Scenes/PROVENANCE.md; docs/CONSTANTS.md).
enum RealScene: String, CaseIterable, Sendable {
    case iphone12ProRAW = "iphone12pro-proraw"
    case pixel8ProDNG = "pixel8pro-dng"

    var sourceName: String {
        switch self {
        case .iphone12ProRAW: "iPhone12Pro_ProRAW_CC0.DNG"
        case .pixel8ProDNG: "Pixel8Pro_CC0.dng"
        }
    }

    static let developDimension: CGFloat = 960
    static let frozenLongEdge: CGFloat = 240

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
