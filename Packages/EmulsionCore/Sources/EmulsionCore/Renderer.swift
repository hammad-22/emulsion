import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders a Negative with the Emulsion look and the user's adjustments, through the film process
/// or the digicam process (`Renderer+Digicam.swift`). One instance per render actor; previews and
/// exports run the same graph, with spatial effects sized relative to the image so they agree
/// across resolutions.
///
/// `@unchecked Sendable`: every stored property is a `let`. `CIContext` is thread-safe (Apple:
/// CIContext.h), and the loaded `CIColorKernel`s are only read.
public final class Renderer: @unchecked Sendable {
    public static let outputSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    /// Core Image working space: extended linear sRGB, half float.
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let kernels: Kernels
    let digicamKernels: DigicamKernels
    public let developer: Developer
    /// For every render but viewfinder frames, and the developer's, which renders each RAW decode into a buffer here:
    /// a full-size decode comes back with corrupted tiles from a context that doesn't cache intermediates (MOV-147,
    /// docs/ENGINE.md). Each render clears the caches after itself.
    private let context: CIContext
    /// Viewfinder frames only (`viewfinderImage`), which hold no RAW decode, so they skip the
    /// caching context's per-frame cache write and clear (+0.8 ms per 1600 px frame, Mac).
    private let viewfinderContext: CIContext
    static var contextOptions: [CIContextOption: Any] {
        [
            .workingColorSpace: workingSpace, .workingFormat: CIFormat.RGBAh, .outputColorSpace: outputSpace,
            .cacheIntermediates: true,
        ]
    }

    public init() throws {
        let library = try Kernels.library()
        kernels = try Kernels(library: library)
        digicamKernels = try DigicamKernels(library: library)
        context = CIContext(options: Self.contextOptions)
        viewfinderContext = CIContext(options: Self.contextOptions.merging([.cacheIntermediates: false]) { $1 })
        developer = Developer(kernels: kernels, context: context)
    }

    /// Scene light → display light (in the working space), look applied. Display-referred
    /// negatives are printed relative to the photo they were developed from. The digicam process
    /// crops to 4:3, caps the size at its sensor's and compresses exports (`renderDigicam`); the film
    /// process renders previews and exports alike.
    public func render(_ negative: Negative, _ adjustments: Adjustments, intent: RenderIntent = .preview) throws -> CIImage {
        let a = adjustments.clamped()
        switch a.process {
        case .film: return try renderFilm(negative, a)
        case .digicam: return try renderDigicam(negative, a, intent: intent)
        }
    }

    private func renderFilm(_ negative: Negative, _ a: Adjustments) throws -> CIImage {
        var image = negative.image
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)

        // Halation is an exposure effect, computed in scene light. Exposure is applied later
        // (in the film kernel), so the threshold is scaled by 2^-exposure instead (MOV-102).
        if a.halation > 0 {
            let threshold = FilmLook.halationThreshold / pow(2, a.exposure)
            let source = try kernels.run(kernels.halationSource, extent, [image, threshold])
            let core = Self.lowResBlur(source, sigma: FilmLook.halationRadius * longEdge)
            let skirt = Self.lowResBlur(source, sigma: FilmLook.halationSkirt * longEdge)
            let coreShare = FilmLook.halationCoreShare
            image = try kernels.run(kernels.halationAdd, extent, [image, core.cropped(to: extent), a.halation * coreShare])
            image = try kernels.run(kernels.halationAdd, extent, [image, skirt.cropped(to: extent), a.halation * (1 - coreShare)])
        }

        if negative.contract == .displayReferred {
            // A finished picture is printed relative to itself: zero edits reproduce it up to the
            // output gamut fit (chroma above 85% of the P3 boundary is compressed).
            let film = FilmLook.stock.relativeKernelArguments(lights: a.printerLights, exposure: a.exposure, saturation: a.printSaturation)
            image = try kernels.run(kernels.filmSystemRelative, extent, [image, negative.image] + film)
        } else {
            let film = FilmLook.stock.kernelArguments(lights: a.printerLights, exposure: a.exposure, saturation: a.printSaturation)
            image = try kernels.run(kernels.filmSystem, extent, [image] + film)
        }

        if a.highlights != 0 || a.shadows != 0 {
            image = try kernels.applyLocalTone(image, shadows: a.shadows, highlights: a.highlights)
        }

        if a.grain > 0 {
            let cell = FilmLook.grainCell * longEdge
            // Sub-pixel cells: lower the amplitude to what pixel averaging would give.
            let correction = min(1, cell)
            image = try kernels.run(kernels.grain, extent, [image, CIVector(x: a.grain, y: max(cell, 1), z: a.seed, w: correction)])
        }
        return image.cropped(to: extent)
    }

    /// Blurs at reduced scale: exact 2×2 halvings keep the energy of small highlights.
    static func lowResBlur(_ image: CIImage, sigma: Double) -> CIImage {
        let maxHalvings = 3
        let minBlurPixels = 2.0
        var levels = 0
        while levels < maxHalvings && sigma / pow(2, Double(levels + 1)) >= minBlurPixels { levels += 1 }
        var small = image.clampedToExtent()
        for _ in 0..<levels { small = small.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)) }
        let factor = pow(2, CGFloat(levels))
        return small.applyingGaussianBlur(sigma: sigma / Double(factor))
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
    }

    /// Render a negative once into a half-float buffer so interactive edits only re-run the look. RAW develops
    /// already are one (`RAWDecoder.negative`); extended-range values are preserved.
    public func materialize(_ negative: Negative) throws -> Negative {
        guard negative.image.pixelBuffer == nil else { return negative }
        return Negative(
            image: try context.renderedToBuffer(negative.image, colorSpace: Self.workingSpace), contract: negative.contract,
            exposureAnchorStops: negative.exposureAnchorStops, asShotWhiteBalance: negative.asShotWhiteBalance)
    }

    public func resized(_ negative: Negative, longestEdge: CGFloat) -> Negative {
        let scale = min(1, longestEdge / max(negative.size.width, negative.size.height))
        guard scale < 1 else { return negative }
        let image = negative.image.lanczosScaled(by: scale)
        let e = CGRect(x: 0, y: 0, width: floor(negative.size.width * scale), height: floor(negative.size.height * scale))
        return Negative(
            image: image.cropped(to: e), contract: negative.contract, exposureAnchorStops: negative.exposureAnchorStops,
            asShotWhiteBalance: negative.asShotWhiteBalance)
    }

    public func cgImage(_ image: CIImage) throws -> CGImage {
        defer { context.clearCaches() }
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: Self.outputSpace) else {
            throw EmulsionError.renderFailed
        }
        return cg
    }

    /// A viewfinder frame (`Developer.viewfinderNegative(from:)`) with the look. Throws for any other
    /// negative: only a camera frame's preview estimate is known to hold no RAW decode.
    public func viewfinderImage(_ negative: Negative, _ adjustments: Adjustments) throws -> CGImage {
        guard negative.contract == .previewEstimate else { throw EmulsionError.renderFailed }
        let image = try render(negative, adjustments)
        guard let cg = viewfinderContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: Self.outputSpace)
        else { throw EmulsionError.renderFailed }
        return cg
    }

    public enum ExportFormat: String, CaseIterable, Codable, Sendable { case jpeg, heic }

    /// Display P3 file with the look baked in; source metadata (GPS etc.) is not carried over.
    public func export(_ image: CIImage, format: ExportFormat, quality: Double = 0.95) throws -> Data {
        switch format {
        case .jpeg: return try jpegData(image, colorSpace: Self.outputSpace, quality: quality)
        case .heic:
            defer { context.clearCaches() }
            guard
                let data = try? context.heif10Representation(
                    of: image.settingProperties([:]), colorSpace: Self.outputSpace, options: Self.options(quality: quality))
            else { throw EmulsionError.renderFailed }
            return data
        }
    }

    /// A JPEG of `image` in `colorSpace`, with the image's properties cleared: Core Image writes them
    /// into the file, and they survive the render, so the source's metadata (GPS included) would
    /// otherwise be carried over (MOV-126).
    /// Through the caching context, like every render that may hold a full-size RAW decode (MOV-147).
    func jpegData(_ image: CIImage, colorSpace: CGColorSpace, quality: Double) throws -> Data {
        defer { context.clearCaches() }
        guard
            let data = context.jpegRepresentation(
                of: image.settingProperties([:]), colorSpace: colorSpace, options: Self.options(quality: quality))
        else { throw EmulsionError.renderFailed }
        return data
    }

    private static func options(quality: Double) -> [CIImageRepresentationOption: Any] {
        [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
    }
}
