import CoreGraphics
import CoreImage
import EmulsionCore
import Foundation
import ImageIO
import Synchronization

/// All developing and rendering happens off the main actor, through one Renderer. Library
/// renders run on this actor, which caches developed previews so slider moves only re-run the
/// look; viewfinder frames run beside it (`viewfinderImage`), so they never wait behind a library
/// render.
public actor RenderService {
    public static let shared = RenderService()
    private var renderer: Renderer?
    /// The same renderer once `prepareViewfinder` has run, for frames rendered off the actor.
    /// `Renderer` is immutable apart from its `CIContext`, which is thread-safe.
    private nonisolated let viewfinderRenderer = Mutex<Renderer?>(nil)
    private var previews: [String: Negative] = [:]
    /// Least recently developed first; the oldest preview is dropped past `maxCachedPreviews`.
    private var lruKeys: [String] = []
    private let maxCachedPreviews = 12
    /// Preview sizes are rounded up to this step, so resizes (iPhone Duo fold/unfold, Mac
    /// windows) reuse a cached develop instead of decoding the RAW again for every size.
    private let previewSizeStep: CGFloat = 256
    private nonisolated let thumbnails: ThumbnailCache
    private nonisolated let latestRenders: LatestRenderCache

    /// Tests pass one renderer to every service so they don't each start a GPU context
    /// (MOV-127), and caches the system never purges so caching is checkable (MOV-130).
    init(
        renderer: Renderer? = nil, thumbnails: ThumbnailCache = ThumbnailCache(),
        latestRenders: LatestRenderCache = LatestRenderCache()
    ) {
        self.renderer = renderer
        self.thumbnails = thumbnails
        self.latestRenders = latestRenders
    }

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
        latestRenders.keep(image, url, maxDimension: maxDimension)
        return image
    }

    /// The last editor-sized film render of this photo, whatever its edit or size: a stand-in
    /// while a rebuilt view renders again. Never an original. Safe to call from the main actor.
    public nonisolated func latestRender(_ url: URL) -> CGImage? {
        latestRenders.image(url)
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

    /// A viewfinder frame, upright and fitted within `maxDimension`, with the film look.
    ///
    /// It previews the RAW render; it isn't the same develop. The camera's processed,
    /// display-referred video frame gets an approximate preview of the scene estimate
    /// (`Developer.viewfinderNegative(from:)`), which is printed absolutely, like a RAW capture;
    /// the saved photo is developed from RAW by `Developer`. After that both run the identical
    /// look. Differences come from Apple's video processing (tone mapping, white balance, noise
    /// reduction, highlight clipping) and are unmeasured until device testing (MOV-121).
    /// Each frame is read back into a CGImage; zero-copy Metal presentation is MOV-12.
    /// Runs off this actor, so it never queues behind a library render.
    @concurrent public nonisolated func viewfinderImage(
        _ frame: CameraFrame, _ adjustments: Adjustments, maxDimension: CGFloat
    ) async throws -> CGImage {
        let renderer = try await preparedViewfinderRenderer()
        let negative = renderer.developer.viewfinderNegative(from: Self.fitted(frame.uprightImage, maxDimension: maxDimension))
        return try renderer.cgImage(renderer.render(negative, adjustments))
    }

    /// Loads the renderer and samples the viewfinder's preview inverse, so the first frame
    /// doesn't wait for either.
    public func prepareViewfinder() throws {
        let renderer = try engine()
        let pixel = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = renderer.developer.viewfinderNegative(from: pixel)
        viewfinderRenderer.withLock { $0 = renderer }
    }

    private nonisolated func preparedViewfinderRenderer() async throws -> Renderer {
        if let renderer = viewfinderRenderer.withLock({ $0 }) { return renderer }
        try await prepareViewfinder()
        guard let renderer = viewfinderRenderer.withLock({ $0 }) else { throw EmulsionError.renderFailed }
        return renderer
    }

    /// The image moved to the origin and scaled down to fit within `maxDimension`. A plain affine
    /// scale, not Lanczos like `Renderer.resized`: cheaper, for the 30 fps path.
    private static func fitted(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let atOrigin = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = min(1, maxDimension / max(atOrigin.extent.width, atOrigin.extent.height))
        let fitted = atOrigin.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Floored from the exact scaled size, as `Renderer.resized` does: no partly covered edge
        // row or column (the transformed extent itself is already rounded outward).
        let size = CGSize(width: (atOrigin.extent.width * scale).rounded(.down), height: (atOrigin.extent.height * scale).rounded(.down))
        return fitted.cropped(to: CGRect(origin: .zero, size: size))
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
        latestRenders.remove(url)
    }

    /// Cache keys, least recently developed first; for tests.
    var cachedPreviewKeys: [String] { lruKeys }
}
