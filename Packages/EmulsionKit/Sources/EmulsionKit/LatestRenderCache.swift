import CoreGraphics
import Foundation

/// The most recent editor-sized film render of each photo, so a photo view rebuilt in a new
/// layout (folding or unfolding iPhone Duo, opening the editor from the library preview)
/// shows the photo at once while it renders again at its new size. Never holds an original.
///
/// `@unchecked Sendable` is safe: the state is an `NSCache`, which Apple documents as
/// thread-safe, and a dictionary only touched under `lock`, both holding immutable `CGImage`s.
final class LatestRenderCache: @unchecked Sendable {
    /// The editor's photo plus the library preview: the large views that get rebuilt.
    static let countLimit = 2
    /// The app's store: the system may purge it whenever memory is short.
    private let images = NSCache<NSString, CGImage>()
    /// The tests' store: never purged, so whether a render was kept is checkable (MOV-130).
    private var unpurged: [NSString: CGImage] = [:]
    private let lock = NSLock()
    private let purgesUnderMemoryPressure: Bool

    init(purgesUnderMemoryPressure: Bool = true) {
        self.purgesUnderMemoryPressure = purgesUnderMemoryPressure
        images.countLimit = Self.countLimit
    }

    func image(_ url: URL) -> CGImage? {
        purgesUnderMemoryPressure ? images.object(forKey: key(url)) : lock.withLock { unpurged[key(url)] }
    }

    /// Thumbnail-sized renders are skipped: the grid would otherwise push out the photo being
    /// edited, and `ThumbnailCache` already keeps those.
    func keep(_ image: CGImage, _ url: URL, maxDimension: CGFloat) {
        guard maxDimension > ThumbnailCache.maxDimension else { return }
        if purgesUnderMemoryPressure {
            images.setObject(image, forKey: key(url))
        } else {
            lock.withLock { unpurged[key(url)] = image }
        }
    }

    func remove(_ url: URL) {
        images.removeObject(forKey: key(url))
        lock.withLock { unpurged[key(url)] = nil }
    }

    private func key(_ url: URL) -> NSString { url.absoluteString as NSString }
}
