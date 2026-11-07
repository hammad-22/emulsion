import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A developed photo in scene-referred linear light, ready for the look.
public struct Negative: @unchecked Sendable {
    public enum Source: Sendable { case raw, display }
    public let image: CIImage
    public let source: Source
    public var size: CGSize { image.extent.size }
}

/// Turns camera data into scene light. RAW (ProRAW or Bayer DNG) goes through Apple's
/// CIRAWFilter with its look processing switched off; display-referred photos are brought
/// back to approximate scene light through the inverse of the neutral film curve.
public struct Developer {
    private let kernels: Kernels
    init(kernels: Kernels) { self.kernels = kernels }

    public static func isRAW(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source), let uti = UTType(type as String)
        else { return false }
        return uti.conforms(to: .rawImage)
    }

    /// `maxDimension` develops a smaller image (RAW draft mode) for fast previews.
    public func develop(_ data: Data, maxDimension: CGFloat? = nil) throws -> Negative {
        if Self.isRAW(data), let raw = CIRAWFilter(imageData: data, identifierHint: nil) {
            // Bypass Apple's rendering: no tone boost, no local tone mapping, no extra
            // contrast. What remains is demosaiced, white-balanced, linear scene light.
            raw.boostAmount = 0
            raw.boostShadowAmount = 0
            if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
            if raw.isContrastSupported { raw.contrastAmount = 0 }
            raw.extendedDynamicRangeAmount = 0
            if let maxDimension {
                let native = raw.nativeSize
                let scale = min(1, maxDimension / max(native.width, native.height))
                raw.scaleFactor = Float(scale)
                raw.isDraftModeEnabled = scale < 1
            }
            guard let output = raw.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else {
                throw EmulsionError.unsupportedPhoto
            }
            return Negative(image: normalized(output), source: .raw)
        }
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true, .toneMapHDRtoSDR: true]),
            !image.extent.isEmpty, !image.extent.isInfinite
        else { throw EmulsionError.unsupportedPhoto }
        if let maxDimension {
            let scale = min(1, maxDimension / max(image.extent.width, image.extent.height))
            if scale < 1 {
                image = image.lanczosScaled(by: scale)
            }
        }
        return try sceneFromDisplay(normalized(image))
    }

    /// Display-referred linear image → scene light (neutral inverse film curve).
    public func sceneFromDisplay(_ image: CIImage) throws -> Negative {
        let args: [Any] = [image] + FilmLook.stock.kernelArguments()
        return Negative(image: try kernels.run(kernels.displayToScene, image.extent, args), source: .display)
    }

    /// Decode raw code values (an image created without color matching, e.g. a video frame's
    /// pixel buffer) from a camera or display encoding into scene light.
    public func scene(fromEncoded image: CIImage, as space: InputColorSpace) throws -> Negative {
        let m = space.toWorking
        let rows = (0..<3).map { CIVector(row: $0, of: m) }
        let linear = try kernels.run(kernels.inputTransform, image.extent, [image, Double(space.curve)] + rows)
        return space.isDisplayReferred ? try sceneFromDisplay(linear) : Negative(image: linear, source: .raw)
    }

    private func normalized(_ image: CIImage) -> CIImage {
        let e = image.extent.integral
        return image.cropped(to: e).transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }
}

extension CIImage {
    /// High-quality downscale, used for previews and RAW drafts.
    func lanczosScaled(by scale: CGFloat) -> CIImage {
        applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
}
