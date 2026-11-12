import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders a Negative with the Emulsion look and the user's adjustments. One instance per
/// render actor; previews and exports run the same graph, with spatial effects sized
/// relative to the image so they agree across resolutions.
public final class Renderer: @unchecked Sendable {
    public static let outputSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    /// Core Image working space: extended linear sRGB, half float.
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let kernels: Kernels
    /// The film every render prints with; the halation glow and the film kernels take it from here.
    let model = FilmLook.stock
    public let developer: Developer
    private let context: CIContext

    public init() throws {
        kernels = try Kernels()
        context = Self.context(cachesIntermediates: false)
        developer = Developer(kernels: kernels, context: Self.context(cachesIntermediates: true))
    }

    private static func context(cachesIntermediates: Bool) -> CIContext {
        CIContext(options: [
            .workingColorSpace: workingSpace, .workingFormat: CIFormat.RGBAh,
            .outputColorSpace: outputSpace, .cacheIntermediates: cachesIntermediates,
        ])
    }

    /// Scene light → display light (in the working space), look applied. Display-referred
    /// negatives are printed relative to the photo they were developed from.
    public func render(_ negative: Negative, _ adjustments: Adjustments) throws -> CIImage {
        let a = adjustments.clamped()
        let scene = negative.image
        let extent = scene.extent
        // Halation and grain act inside the film kernels, on layer exposure and negative density
        // (see `Halation`, `Grain`); with both off the film kernels run without them.
        let glow = a.halation > 0 ? try kernels.halationGlow(of: scene, model: model, saturation: a.printSaturation) : nil
        let noise = a.grain > 0 ? try kernels.grainNoise(extent, seed: a.seed) : nil
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
            + Grain.kernelArguments(amount: a.grain, longEdge: max(extent.width, extent.height))
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
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: Self.outputSpace) else {
            throw EmulsionError.renderFailed
        }
        return cg
    }

    public enum ExportFormat: String, CaseIterable, Codable, Sendable { case jpeg, heic }

    /// Display P3 file with the look baked in; source metadata (GPS etc.) is not carried over.
    public func export(_ image: CIImage, format: ExportFormat, quality: Double = 0.95) throws -> Data {
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        // Core Image writes an image's properties into the file, and they survive the film
        // render, so the source's metadata (GPS included) is cleared first (MOV-126).
        let image = image.settingProperties([:])
        let data: Data?
        switch format {
        case .jpeg: data = context.jpegRepresentation(of: image, colorSpace: Self.outputSpace, options: options)
        case .heic: data = try? context.heif10Representation(of: image, colorSpace: Self.outputSpace, options: options)
        }
        guard let data else { throw EmulsionError.renderFailed }
        return data
    }
}
