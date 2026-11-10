import CoreGraphics
import EmulsionCore
import Foundation

/// Finished renders small enough to be library thumbnails, so scrolling back to a photo
/// shows it at once instead of developing it again. Larger renders (the editor's preview)
/// change with every slider move and aren't kept.
///
/// `@unchecked Sendable` is safe: the only state is an `NSCache`, which Apple documents as
/// thread-safe, holding immutable `CGImage`s.
final class ThumbnailCache: @unchecked Sendable {
    static let maxDimension: CGFloat = 512
    private let images = NSCache<NSString, CGImage>()

    init() {
        images.totalCostLimit = 64 << 20  // bytes; about 60 thumbnails at 512 px
    }

    func image(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) -> CGImage? {
        key(url, adjustments, maxDimension: maxDimension).flatMap(images.object(forKey:))
    }

    func keep(_ image: CGImage, _ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) {
        guard let key = key(url, adjustments, maxDimension: maxDimension) else { return }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
    }

    func removeAll() {
        images.removeAllObjects()
    }

    /// Nil for sizes too large to be thumbnails. The edit is part of the key as encoded
    /// JSON, so a field added to `Adjustments` can never serve a stale thumbnail.
    private func key(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) -> NSString? {
        guard maxDimension <= Self.maxDimension else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let edit = try? encoder.encode(adjustments) else { return nil }
        return "\(url.absoluteString)@\(Int(maxDimension.rounded(.up)))#\(String(decoding: edit, as: UTF8.self))" as NSString
    }
}
