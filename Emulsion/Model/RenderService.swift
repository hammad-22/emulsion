import CoreGraphics
import EmulsionCore
import Foundation

/// All developing and rendering happens off the main actor, through one Renderer.
/// Developed previews are cached so slider moves only re-run the look.
actor RenderService {
    static let shared = RenderService()
    private var renderer: Renderer?
    private var previews: [String: Negative] = [:]
    /// Least recently developed first; the oldest preview is dropped past `maxCachedPreviews`.
    private var lruKeys: [String] = []
    private let maxCachedPreviews = 12
    /// Preview sizes are rounded up to this step, so resizes (iPhone Duo fold/unfold, Mac
    /// windows) reuse a cached develop instead of decoding the RAW again for every size.
    private let previewSizeStep: CGFloat = 256

    private func engine() throws -> Renderer {
        if let renderer { return renderer }
        let new = try Renderer()
        renderer = new
        return new
    }

    private func negative(_ url: URL, maxDimension requested: CGFloat) throws -> Negative {
        let maxDimension = (requested / previewSizeStep).rounded(.up) * previewSizeStep
        let key = "\(url.lastPathComponent)@\(Int(maxDimension))"
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

    func image(_ url: URL, _ adjustments: Adjustments, maxDimension: CGFloat) throws -> CGImage {
        let renderer = try engine()
        return try renderer.cgImage(renderer.render(negative(url, maxDimension: maxDimension), adjustments))
    }

    /// Full-resolution develop and encode, look baked in.
    func export(_ url: URL, _ adjustments: Adjustments, format: Renderer.ExportFormat) throws -> Data {
        let renderer = try engine()
        let full = try renderer.developer.develop(Data(contentsOf: url))
        return try renderer.export(renderer.render(full, adjustments), format: format)
    }

    /// Drops every cached preview of a photo (after it's deleted or its source changes).
    func forget(_ url: URL) {
        let prefix = url.lastPathComponent + "@"
        for key in previews.keys where key.hasPrefix(prefix) { previews[key] = nil }
        lruKeys.removeAll { $0.hasPrefix(prefix) }
    }
}
