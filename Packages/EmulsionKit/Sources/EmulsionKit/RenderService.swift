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
    /// One develop per photo and size, with the RAW white balance it was developed at: another
    /// white balance replaces it, so dragging the temperature doesn't fill the cache. A photo that
    /// isn't RAW (no `asShotWhiteBalance`) is never developed again for a white balance. The open
    /// photo develops again from its kept decoder (`openDecoder`); any other reads its file again.
    private var previews: [String: (negative: Negative, whiteBalance: CameraWhiteBalance?)] = [:]
    /// Least recently used first; the oldest preview is dropped past `maxCachedPreviews`.
    private var lruKeys: [String] = []
    private let maxCachedPreviews = 12
    /// Preview sizes are rounded up to this step, so resizes (iPhone Duo fold/unfold, Mac
    /// windows) reuse a cached develop instead of decoding the RAW again for every size.
    private let previewSizeStep: CGFloat = 256
    /// Each file's exposure anchor from its first develop, so later develops (other sizes, white
    /// balances, export) skip measuring it. In memory only; keeping it on the photo record is a follow-up.
    private var exposureAnchors: [URL: Double] = [:]
    /// The photo open in the editor, set from the main actor before its first render is asked for.
    private nonisolated let openPhoto = Mutex<URL?>(nil)
    /// The open photo's RAW decoder, kept so a white balance drag renders each step without
    /// reading or decoding the file again (MOV-137). Only ever one: it holds the file's bytes and
    /// Apple's decode. `maxDimension` is the largest preview asked for so far; smaller ones are
    /// resized from it.
    private var openDecoder: (url: URL, maxDimension: CGFloat, decoder: RAWDecoder)?
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

    private func negative(_ url: URL, maxDimension requested: CGFloat, whiteBalance: CameraWhiteBalance?) throws -> Negative {
        let maxDimension = (requested / previewSizeStep).rounded(.up) * previewSizeStep
        let key = "\(url.absoluteString)@\(Int(maxDimension))"
        if let cached = previews[key], cached.negative.asShotWhiteBalance == nil || cached.whiteBalance == whiteBalance {
            markUsed(key)
            return cached.negative
        }
        let renderer = try engine()
        let developed =
            try openDecoder(for: url, maxDimension: maxDimension)?.negative(whiteBalance: whiteBalance)
            ?? develop(url, maxDimension: maxDimension, whiteBalance: whiteBalance)
        developCount += 1
        // Draft RAW decode may come back larger than asked; fit it exactly. Then render it
        // once into a half-float buffer, so slider moves don't redo the RAW develop or the
        // JPEG inversion (Core Image doesn't cache intermediates for us).
        let fitted = try renderer.materialize(renderer.resized(developed, longestEdge: maxDimension))
        previews[key] = (fitted, whiteBalance)
        markUsed(key)
        if lruKeys.count > maxCachedPreviews { previews[lruKeys.removeFirst()] = nil }
        return fitted
    }

    private func markUsed(_ key: String) {
        lruKeys.removeAll { $0 == key }
        lruKeys.append(key)
    }

    /// A rendered preview. Throws `CancellationError` if the caller moved on while it waited
    /// its turn, so slider drags don't queue up stale renders.
    public func image(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) throws -> CGImage {
        if let cached = cachedThumbnail(url, adjustments, maxDimension: maxDimension) { return cached }
        try Task.checkCancellation()
        let renderer = try engine()
        let image = try renderer.cgImage(
            renderer.render(negative(url, maxDimension: maxDimension, whiteBalance: adjustments.whiteBalance), adjustments))
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
        let full = try develop(url, maxDimension: nil, whiteBalance: adjustments.whiteBalance)
        return try renderer.export(renderer.render(full, adjustments), format: format)
    }

    /// Reads and develops the file with its exposure anchor, measuring and remembering it the
    /// first time; the anchor is measured as shot, so a white balance change reuses it.
    private func develop(_ url: URL, maxDimension: CGFloat?, whiteBalance: CameraWhiteBalance?) throws -> Negative {
        let developed = try engine().developer.develop(
            Self.contents(of: url), maxDimension: maxDimension, whiteBalance: whiteBalance,
            exposureAnchorStops: exposureAnchors[url])
        fileReadCount += 1
        exposureAnchors[url] = developed.exposureAnchorStops
        return developed
    }

    /// The open photo's decoder, large enough for `maxDimension`: the kept one, or a new one made
    /// by reading the file. Nil when `url` isn't the open photo or isn't RAW. A kept decoder that
    /// is too small or no longer the open photo's is released first, so two files' decodes are
    /// never held at once.
    private func openDecoder(for url: URL, maxDimension: CGFloat) throws -> RAWDecoder? {
        let open = openPhoto.withLock { $0 }
        if let kept = openDecoder, kept.url != open || (kept.url == url && kept.maxDimension < maxDimension) { openDecoder = nil }
        guard open == url else { return nil }
        if let kept = openDecoder { return kept.decoder }
        guard
            let decoder = try engine().developer.rawDecoder(
                Self.contents(of: url), maxDimension: maxDimension, exposureAnchorStops: exposureAnchors[url])
        else { return nil }
        fileReadCount += 1
        exposureAnchors[url] = decoder.exposureAnchorStops
        openDecoder = (url, maxDimension, decoder)
        return decoder
    }

    /// The file's bytes, mapped where that's safe: a kept decoder holds them for as long as the
    /// editor is open, and mapped pages can be dropped and read back instead of staying in memory.
    private static func contents(of url: URL) throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Marks the photo open in the editor: its RAW decoder is kept from its next develop, so
    /// white balance changes render without decoding the file again. One photo at a time; the
    /// last one's decoder is released at the next develop. Call before asking for its first render.
    public nonisolated func open(_ url: URL) {
        openPhoto.withLock { $0 = url }
    }

    /// The photo's editor went away: its kept RAW decoder is released, unless the photo was
    /// opened again meanwhile. The returned task finishes once it is.
    @discardableResult public nonisolated func close(_ url: URL) -> Task<Void, Never> {
        openPhoto.withLock { if $0 == url { $0 = nil } }
        return Task { await releaseClosedDecoder() }
    }

    private func releaseClosedDecoder() {
        if openDecoder?.url != openPhoto.withLock({ $0 }) { openDecoder = nil }
    }

    /// The white balance a RAW photo was shot at, read from the file without developing it; nil
    /// when it isn't RAW or can't be read. Runs off this actor, so it never waits behind a render.
    @concurrent public nonisolated func asShotWhiteBalance(_ url: URL) async -> CameraWhiteBalance? {
        (try? Self.contents(of: url)).flatMap(Developer.asShotWhiteBalance(of:))
    }

    /// Drops every cached preview, the exposure anchor and a kept decoder of a photo (after it's
    /// deleted or its source changes).
    public func forget(_ url: URL) {
        exposureAnchors[url] = nil
        if openDecoder?.url == url { openDecoder = nil }
        let prefix = url.absoluteString + "@"
        for key in previews.keys where key.hasPrefix(prefix) { previews[key] = nil }
        lruKeys.removeAll { $0.hasPrefix(prefix) }
        thumbnails.removeAll()
        latestRenders.remove(url)
    }

    /// Cache keys, least recently used first; for tests.
    var cachedPreviewKeys: [String] { lruKeys }
    /// Previews developed so far, cache misses; for tests.
    private(set) var developCount = 0
    /// Times a file was read to develop a preview or an export, or to make a decoder; for tests.
    private(set) var fileReadCount = 0
    /// The photo whose RAW decoder is kept; for tests.
    var keptDecoderURL: URL? { openDecoder?.url }
    /// The file's remembered exposure anchor; for tests.
    func exposureAnchor(_ url: URL) -> Double? { exposureAnchors[url] }
}
