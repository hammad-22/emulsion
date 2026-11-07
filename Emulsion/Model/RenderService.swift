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

    private func engine() throws -> Renderer {
        if let renderer { return renderer }
        let new = try Renderer()
        renderer = new
        return new
    }

    private func negative(_ url: URL, maxDimension: CGFloat) throws -> Negative {
        let key = "\(url.lastPathComponent)@\(Int(maxDimension))"
        if let cached = previews[key] { return cached }
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

    /// Drops cached previews of a photo (for the delete flow, not wired yet).
    func forget(_ url: URL) {
        let prefix = url.lastPathComponent + "@"
        for key in previews.keys where key.hasPrefix(prefix) { previews[key] = nil }
        lruKeys.removeAll { $0.hasPrefix(prefix) }
    }
}
