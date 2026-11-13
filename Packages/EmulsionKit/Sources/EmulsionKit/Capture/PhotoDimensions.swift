import Foundation

/// A photo size the camera can capture at, in pixels.
struct PhotoDimensions: Sendable, Equatable {
    let width: Int32
    let height: Int32
    var pixelCount: Int { Int(width) * Int(height) }

    /// The nominal "12 MP" of the Standard setting.
    private static let standardPixelCount = 12_000_000

    /// Full: the largest size. Standard: the size nearest 12 MP. Nil when there's none.
    static func choose(_ resolution: AppSettings.Resolution, from supported: [PhotoDimensions]) -> PhotoDimensions? {
        switch resolution {
        case .full: supported.max { $0.pixelCount < $1.pixelCount }
        case .standard: supported.min { abs($0.pixelCount - standardPixelCount) < abs($1.pixelCount - standardPixelCount) }
        }
    }

    /// True when Full picks a larger size than Standard.
    static func supportsFullResolution(_ supported: [PhotoDimensions]) -> Bool {
        guard let full = choose(.full, from: supported), let standard = choose(.standard, from: supported) else { return false }
        return full.pixelCount > standard.pixelCount
    }
}
