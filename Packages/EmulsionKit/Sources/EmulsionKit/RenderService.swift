import CoreGraphics
import EmulsionCore
import Foundation
import ImageIO

/// All developing and rendering happens off the main actor, through one Renderer.
/// Developed previews are cached so slider moves only re-run the look.
public actor RenderService {
    public static let shared = RenderService()
    private var renderer: Renderer?
    private var previews: [String: Negative] = [:]
    /// Least recently developed first; the oldest preview is dropped past `maxCachedPreviews`.
    private var lruKeys: [String] = []
    private let maxCachedPreviews = 12
    /// Preview sizes are rounded up to this step, so resizes (iPhone Duo fold/unfold, Mac
    /// windows) reuse a cached develop instead of decoding the RAW again for every size.
    private let previewSizeStep: CGFloat = 256
    private nonisolated let thumbnails = ThumbnailCache()

    init() {}

    private func engine() throws -> Renderer {
        if let renderer { return renderer }
        let new = try Renderer()
        renderer = new
        return new
    }

    private func negative(_ url: URL, maxDimension requested: CGFloat) throws -> Negative {
        let maxDimension = (requested / previewSizeStep).rounded(.up) * previewSizeStep
        let key = "\(url.absoluteString)@\(Int(maxDimension))"
        if let cached = previews[key] {
            lruKeys.removeAll { $0 == key }
            lruKeys.append(key)
            return cached
        }
        let renderer = try engine()
        let developed = try renderer.developer.develop(Data(contentsOf: url), maxDimension: maxDimension)
        // Draft RAW decode may come back larger than asked; fit it exactly. Then render it
        // once into a half-float buffer, so slider moves don't redo the RAW develop or the
        // JPEG inversion (Core Image doesn't cache intermediates for us).
        let fitted = try renderer.materialize(renderer.resized(developed, longestEdge: maxDimension))
        previews[key] = fitted
        lruKeys.append(key)
        if lruKeys.count > maxCachedPreviews { previews[lruKeys.removeFirst()] = nil }
        return fitted
    }

    /// A rendered preview. Throws `CancellationError` if the caller moved on while it waited
    /// its turn, so slider drags don't queue up stale renders.
    public func image(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) throws -> CGImage {
        if let cached = cachedThumbnail(url, adjustments, maxDimension: maxDimension) { return cached }
        try Task.checkCancellation()
        let renderer = try engine()
        let image = try renderer.cgImage(renderer.render(negative(url, maxDimension: maxDimension), adjustments))
        thumbnails.keep(image, url, adjustments, maxDimension: maxDimension)
        return image
    }

    /// A thumbnail already rendered with exactly this edit, if it's still cached. Safe to
    /// call from the main actor: it encodes the edit key and looks the image up.
    public nonisolated func cachedThumbnail(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) -> CGImage? {
        thumbnails.image(url, adjustments, maxDimension: maxDimension)
    }

    /// The original photo as the camera or app delivered it, without the film process: the
    /// "before" in before/after. RAW files show their embedded preview when they have one.
    /// Touches no actor state, so it runs off both this actor and the caller's: it never
    /// waits behind a queued film render, and never decodes on the main actor.
    @concurrent public nonisolated func original(_ url: URL, maxDimension: CGFloat) async throws -> CGImage {
        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension.rounded(.up)),
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw EmulsionError.unsupportedPhoto }
        return image
    }

    /// Full-resolution develop and encode, look baked in.
    public func export(_ url: URL, _ adjustments: Adjustments, format: Renderer.ExportFormat) throws -> Data {
        let renderer = try engine()
        let full = try renderer.developer.develop(Data(contentsOf: url))
        return try renderer.export(renderer.render(full, adjustments), format: format)
    }

    /// Drops every cached preview of a photo (after it's deleted or its source changes).
    public func forget(_ url: URL) {
        let prefix = url.absoluteString + "@"
        for key in previews.keys where key.hasPrefix(prefix) { previews[key] = nil }
        lruKeys.removeAll { $0.hasPrefix(prefix) }
        thumbnails.removeAll()
    }

    /// Cache keys, least recently developed first; for tests.
    var cachedPreviewKeys: [String] { lruKeys }
}
