import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A developed photo in linear working-space light, ready for the look. `contract` says what
/// that light is: scene light, nominal scene light, or (for display-referred sources) a scene
/// estimate that the renderer prints relative to the photo, so zero edits reproduce it up to
/// the output gamut fit (which compresses chroma above 85% of the P3 boundary).
public struct Negative: @unchecked Sendable {
    public let image: CIImage
    public let contract: InputContract
    public var size: CGSize { image.extent.size }
}

/// Turns camera data into linear light for the film system. RAW (ProRAW or Bayer DNG) goes
/// through Apple's CIRAWFilter with its look processing switched off. Display-referred photos
/// only get an estimate of scene light from the neutral film curve: the camera's rendering
/// can't be undone.
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
            return Negative(image: normalized(output), contract: .sceneReferred)
        }
        // Known limitation: HDR stills are read as their SDR rendition (a gain map is ignored,
        // PQ/HLG stills are tone-mapped by Core Image), so HDR headroom is discarded until MOV-49.
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

    /// Display-referred linear image → a scene estimate: per channel, the neutral exposure whose
    /// print matches the display value, with white and black held at a finite ceiling and floor
    /// (`FilmModel.sceneEstimate(fromDisplay:)`). Not a recovery of the scene.
    public func sceneFromDisplay(_ image: CIImage) throws -> Negative {
        let args: [Any] = [image] + FilmLook.stock.displayToSceneArguments()
        return Negative(image: try kernels.run(kernels.displayToScene, image.extent, args), contract: .displayReferred)
    }

    /// Decode R′G′B′ code values (an image created without color matching, sample = code / 1023)
    /// coded in `range`, from a camera or display encoding into light under `space.contract`.
    public func scene(fromEncoded image: CIImage, as space: InputColorSpace, range: SignalRange) throws -> Negative {
        try scene(fromWorkingLight: workingLight(fromEncoded: image, as: space, range: range), as: space)
    }

    /// Decode a 10-bit Y′CbCr video frame (`x420`, `xf20`, `x422` or `xf22`) into light under
    /// `space.contract`.
    /// `signal` defaults to the frame's own range and matrix tag; pass it to override a mistagged file.
    /// The frame stays retained and locked while the returned negative's image is alive, so a
    /// frame source should `materialize` (or drop) it before holding it across frames.
    public func scene(fromYCbCr frame: CVPixelBuffer, as space: InputColorSpace, signal: VideoSignal? = nil) throws -> Negative {
        guard let layout = YCbCrLayout(frame), let (luma, chroma) = layout.planes(of: frame) else {
            throw EmulsionError.unsupportedVideoFormat
        }
        let signal = signal ?? VideoSignal(frame: frame, layout: layout, fallbackMatrix: space.defaultYCbCrMatrix)
        let transform = CurveInputTransform(ycbcrIn: signal, sampleUnitsPerCode: YCbCrLayout.sampleUnitsPerCode, for: space)
        let light = try workingLight(kernels.ycbcrInputTransform, luma.extent, [luma, chroma], transform, as: space)
        return try scene(fromWorkingLight: light, as: space)
    }

    /// The input transform alone (curve and gamut matrix): working-space light before display
    /// encodings get their scene estimate.
    func workingLight(fromEncoded image: CIImage, as space: InputColorSpace, range: SignalRange) throws -> CIImage {
        let transform = CurveInputTransform(rgbIn: range, sampleUnitsPerCode: 1 / 1023, for: space)
        return try workingLight(kernels.inputTransform, image.extent, [image], transform, as: space)
    }

    private func workingLight(
        _ kernel: CIColorKernel, _ extent: CGRect, _ images: [CIImage], _ transform: CurveInputTransform, as space: InputColorSpace
    ) throws -> CIImage {
        try kernels.run(kernel, extent, images + transform.rows + [Double(space.curve)] + CIVector.rows(of: space.toWorking))
    }

    private func scene(fromWorkingLight light: CIImage, as space: InputColorSpace) throws -> Negative {
        space.contract == .displayReferred ? try sceneFromDisplay(light) : Negative(image: light, contract: space.contract)
    }

    private func normalized(_ image: CIImage) -> CIImage {
        let e = image.extent.integral
        return image.cropped(to: e).transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }
}
