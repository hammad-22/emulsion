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
        var image = negative.image
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)

        image = try sceneWithHalation(image, a)

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

    /// Scene light with halation added, before the film (see `Halation`). Linear in the scene, so it
    /// commutes with exposure, which the film kernel applies (MOV-102).
    func sceneWithHalation(_ scene: CIImage, _ adjustments: Adjustments) throws -> CIImage {
        let a = adjustments.clamped()
        guard a.halation > 0 else { return scene }
        let extent = scene.extent
        let sensitivity = FilmLook.stock.sensitivity
        let exposure = try kernels.run(kernels.halationSource, extent, [scene] + CIVector.rows(of: sensitivity))
        let mirrored = try mirroredToInfinity(exposure)
        let pixelsPerBase = Halation.pixelsPerBaseThickness(longEdge: max(extent.width, extent.height))
        let sigmas = Halation.sigmasInBaseThicknesses * pixelsPerBase
        let blurs = Self.lowResBlurs(mirrored, sigmas: (0..<3).map { sigmas[$0] }).map { $0.cropped(to: extent) }
        let weights = Halation.weights
        let k = Halation.layerReturn(amount: a.halation, backing: a.backing)
        let arguments: [Any] =
            [scene] + blurs + [CIVector(x: weights.x, y: weights.y, z: weights.z, w: 0), CIVector(x: k.x, y: k.y, z: k.z, w: 0)]
            + CIVector.rows(of: sensitivity) + CIVector.rows(of: sensitivity.inverse)
        return try kernels.run(kernels.halationAdd, extent, arguments)
    }

    /// `image` reflected at its edges, repeating without end (the warp `mirroredEdges`). Unlike
    /// clamping, a bright border pixel is not repeated to infinity (review F-12), and a uniform
    /// field stays uniform up to the border.
    func mirroredToInfinity(_ image: CIImage) throws -> CIImage {
        let e = image.extent
        guard
            let mirrored = kernels.mirroredEdges.apply(
                extent: .infinite, roiCallback: { _, _ in e }, image: image.clampedToExtent().samplingNearest(),
                arguments: [CIVector(cgRect: e)])
        else { throw EmulsionError.renderFailed }
        // An intermediate, so a later scale is not folded into the warp's nearest sampling.
        return mirrored.insertingIntermediate(cache: false)
    }

    /// Gaussian blurs of an infinite image, each at reduced scale. Each halving is its own 2×2
    /// average (an intermediate: Core Image would otherwise fold successive halvings into one sparse
    /// sample and drop small highlights), shared by the blurs. The Gaussian is narrowed by the
    /// variance the halvings (box of N px: (N² − 1)/12) and the bilinear return (N²/6) add, so each
    /// blur's effective sigma is the one asked for.
    static func lowResBlurs(_ image: CIImage, sigmas: [Double]) -> [CIImage] {
        let maxHalvings = 3
        let minBlurPixels = 2.0
        let levels = sigmas.map { sigma in
            (0...maxHalvings).last { $0 == 0 || sigma / pow(2, Double($0)) >= minBlurPixels } ?? 0
        }
        var pyramid = [image]
        for _ in 0..<(levels.max() ?? 0) {
            pyramid.append(
                pyramid[pyramid.count - 1].transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)).insertingIntermediate(cache: false))
        }
        return zip(sigmas, levels).map { sigma, level in
            let n = pow(2, Double(level))
            let added = level == 0 ? 0 : (n * n - 1) / 12 + n * n / 6
            let lowSigma = max(sigma * sigma - added, 0).squareRoot() / n
            return pyramid[level].applyingGaussianBlur(sigma: lowSigma).transformed(by: CGAffineTransform(scaleX: n, y: n))
        }
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
