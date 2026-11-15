import CoreGraphics
import EmulsionCore
import Foundation

/// Finished renders small enough to be library thumbnails, so scrolling back to a photo
/// shows it at once instead of developing it again. Larger renders (the editor's preview)
/// change with every slider move and aren't kept. Kept in memory and, through `files`, on disk.
///
/// `@unchecked Sendable` is safe: the state is an `NSCache`, which Apple documents as
/// thread-safe, a dictionary only touched under `lock`, both holding immutable `CGImage`s, and
/// `files`, which is `Sendable`.
final class ThumbnailCache: @unchecked Sendable {
    static let maxDimension: CGFloat = 512
    /// The app's store: the system may purge it whenever memory is short.
    private let images = NSCache<KeyObject, CGImage>()
    /// The tests' store: never purged, so whether a render was kept is checkable (MOV-130).
    private var unpurged: [Key: CGImage] = [:]
    private let lock = NSLock()
    private let purgesUnderMemoryPressure: Bool
    private let files: ThumbnailFiles?

    init(purgesUnderMemoryPressure: Bool = true, files: ThumbnailFiles? = ThumbnailFiles()) {
        self.purgesUnderMemoryPressure = purgesUnderMemoryPressure
        self.files = files
        images.totalCostLimit = 64 << 20  // bytes; about 60 thumbnails at 512 px
    }

    /// A photo, its whole edit and its size in pixels; nil for sizes too large to be thumbnails.
    /// The edit is compared whole, so a field added to `Adjustments` can never serve a stale thumbnail.
    struct Key: Hashable, Sendable {
        let url: URL
        let adjustments: Adjustments
        let pixels: Int

        init?(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) {
            guard maxDimension <= ThumbnailCache.maxDimension else { return nil }
            self.url = url
            self.adjustments = adjustments
            pixels = Int(maxDimension.rounded(.up))
        }
    }

    /// A thumbnail in memory. Cheap enough for the main actor: it hashes the edit, nothing more.
    func image(_ key: Key) -> CGImage? {
        purgesUnderMemoryPressure ? images.object(forKey: KeyObject(key)) : lock.withLock { unpurged[key] }
    }

    /// A thumbnail stored on disk by an earlier launch, kept in memory once read. Reads a file:
    /// never call it on the main actor.
    func storedImage(_ key: Key) -> CGImage? {
        guard let image = files?.image(key) else { return nil }
        keepInMemory(image, key)
        return image
    }

    func keep(_ image: CGImage, _ key: Key) {
        keepInMemory(image, key)
        files?.keep(image, key)
    }

    /// Forgets every thumbnail in memory and the photo's on disk.
    func remove(_ url: URL) {
        images.removeAllObjects()
        lock.withLock { unpurged.removeAll() }
        files?.remove(url)
    }

    private func keepInMemory(_ image: CGImage, _ key: Key) {
        if purgesUnderMemoryPressure {
            images.setObject(image, forKey: KeyObject(key), cost: image.bytesPerRow * image.height)
        } else {
            lock.withLock { unpurged[key] = image }
        }
    }

    /// `NSCache` needs object keys.
    private final class KeyObject: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyObject)?.key == key }
    }
}
