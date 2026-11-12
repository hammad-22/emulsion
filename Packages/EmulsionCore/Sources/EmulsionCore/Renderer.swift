import CoreImage
import CoreImage.CIFilterBuiltins
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
    private let kernels: Kernels
    public let developer: Developer
    let context: CIContext

    public init() throws {
        kernels = try Kernels()
        context = CIContext(options: [
            .workingColorSpace: Self.workingSpace, .workingFormat: CIFormat.RGBAh,
            .outputColorSpace: Self.outputSpace, .cacheIntermediates: false,
        ])
        developer = Developer(kernels: kernels, context: context)
    }

    /// Scene light → display light (in the working space), look applied. Display-referred
    /// negatives are printed relative to the photo they were developed from.
    public func render(_ negative: Negative, _ adjustments: Adjustments) throws -> CIImage {
        let a = adjustments.clamped()
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
        return Negative(image: image, contract: negative.contract, exposureAnchorStops: negative.exposureAnchorStops)
    }

    public func resized(_ negative: Negative, longestEdge: CGFloat) -> Negative {
        let scale = min(1, longestEdge / max(negative.size.width, negative.size.height))
        guard scale < 1 else { return negative }
        let image = negative.image.lanczosScaled(by: scale)
        let e = CGRect(x: 0, y: 0, width: floor(negative.size.width * scale), height: floor(negative.size.height * scale))
        return Negative(
            image: image.cropped(to: e), contract: negative.contract, exposureAnchorStops: negative.exposureAnchorStops)
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
