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
    /// The film every render prints with; the halation glow and the film kernels take it from here.
    let model = FilmLook.stock
    let digicamKernels: DigicamKernels
    public let developer: Developer
    /// For every render but viewfinder frames, and the developer's: any of these graphs may hold a
    /// RAW decode, and a full-size one comes back with corrupted tiles from a context that doesn't
    /// cache intermediates (MOV-147, docs/ENGINE.md). Each render clears the caches after itself.
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
        let scene = negative.image
        let extent = scene.extent
        // Halation and grain act inside the film kernels, on layer exposure and negative density
        // (see `Halation`, `Grain`); with both off the film kernels run without them.
        let glow = a.halation > 0 ? try kernels.halationGlow(of: scene, model: model, saturation: a.printSaturation) : nil
        let noise = a.grain > 0 ? try kernels.grainNoise(extent, seed: a.seed, size: a.grainSize) : nil
        var image = try filmPrint(negative, glow: glow, noise: noise, a)
        if a.highlights != 0 || a.shadows != 0 {
            image = try kernels.applyLocalTone(image, shadows: a.shadows, highlights: a.highlights)
        }
        return image.cropped(to: extent)
    }

    /// The film kernels: `negative` printed under clamped adjustments `a`, with the halation `glow`
    /// (`Kernels.halationGlow`) and grain `noise` (`Kernels.grainNoise`) over its extent; a missing
    /// one adds exactly nothing (a black sampler, and k = 0 or σ·0). With neither, the variants
    /// without samplers and texture arguments (`filmSystemPlain`, `filmSystemRelativePlain`) run.
    func filmPrint(_ negative: Negative, glow: CIImage?, noise: CIImage?, _ a: Adjustments) throws -> CIImage {
        let extent = negative.image.extent
        let film = model.kernelArguments(lights: a.printerLights, exposure: a.exposure, saturation: a.printSaturation)
        // A finished picture is printed relative to itself: zero edits reproduce it up to the
        // output gamut fit (chroma above 85% of the P3 boundary is compressed).
        let relative = negative.contract == .displayReferred
        let ends = relative ? model.relativeArguments : []
        guard glow != nil || noise != nil else {
            return try kernels.run(
                relative ? kernels.filmSystemRelativePlain : kernels.filmSystemPlain, extent, [negative.image] + film + ends)
        }
        let black = CIImage(color: .black).cropped(to: extent)
        let texture =
            Halation.kernelArguments(for: model, amount: a.halation, backing: a.backing)
            + Grain.kernelArguments(amount: a.grain, size: a.grainSize, color: a.grainColor, longEdge: max(extent.width, extent.height))
        return try kernels.run(
            relative ? kernels.filmSystemRelative : kernels.filmSystem, extent,
            [negative.image, glow ?? black, noise ?? black] + film + ends + texture)
    }

    /// Develop once: render the (lazy) negative into a half-float buffer so interactive edits
    /// only re-run the look, never the RAW demosaic. Extended-range values are preserved.
    public func materialize(_ negative: Negative) throws -> Negative {
        let w = Int(negative.size.width)
        let h = Int(negative.size.height)
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_64RGBAHalf, attributes, &buffer) == kCVReturnSuccess, let buffer else {
            throw EmulsionError.renderFailed
        }
        defer { context.clearCaches() }
        context.render(negative.image, to: buffer, bounds: negative.image.extent, colorSpace: Self.workingSpace)
        let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: Self.workingSpace])
        return Negative(
            image: image, contract: negative.contract, exposureAnchorStops: negative.exposureAnchorStops,
            asShotWhiteBalance: negative.asShotWhiteBalance)
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
