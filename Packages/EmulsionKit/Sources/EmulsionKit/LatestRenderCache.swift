import CoreGraphics
import Foundation

/// Latest editor-sized render per photo, shown at once after a relayout. See NOTES.md, "LatestRenderCache".
/// `@unchecked Sendable` is safe: `NSCache` is thread-safe and `unpurged` is only touched under `lock`.
final class LatestRenderCache: @unchecked Sendable {
    /// The editor's photo plus the library preview.
    static let countLimit = 2
    private let images = NSCache<NSString, CGImage>()
    /// The tests' store: never purged, so caching is checkable (MOV-130).
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
