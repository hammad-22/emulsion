import CoreGraphics
import Foundation

/// The most recent editor-sized film render of each photo, so a photo view rebuilt in a new
/// layout (folding or unfolding iPhone Duo, opening the editor from the library preview)
/// shows the photo at once while it renders again at its new size. Never holds an original.
///
/// `@unchecked Sendable` is safe: the only state is an `NSCache`, which Apple documents as
/// thread-safe, holding immutable `CGImage`s.
final class LatestRenderCache: @unchecked Sendable {
    /// The editor's photo plus the library preview: the large views that get rebuilt.
    static let countLimit = 2
    private let images = NSCache<NSString, CGImage>()

    init() {
        images.countLimit = Self.countLimit
    }

    func image(_ url: URL) -> CGImage? {
        images.object(forKey: key(url))
    }

    /// Thumbnail-sized renders are skipped: the grid would otherwise push out the photo being
    /// edited, and `ThumbnailCache` already keeps those.
    func keep(_ image: CGImage, _ url: URL, maxDimension: CGFloat) {
        guard maxDimension > ThumbnailCache.maxDimension else { return }
        images.setObject(image, forKey: key(url))
    }

    func remove(_ url: URL) {
        images.removeObject(forKey: key(url))
    }

    private func key(_ url: URL) -> NSString { url.absoluteString as NSString }
}
