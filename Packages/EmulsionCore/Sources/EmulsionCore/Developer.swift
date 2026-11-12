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
    /// Stops added at develop so the tones the RAW file's DNG profile renders at mid-gray sit at
    /// scene 0.18: one exact multiply by 2^stops (undo it with −stops). Chosen from the file's own
    /// pixels, so it follows the scene (two shots from one camera can differ); an estimate, not a
    /// metered level. 0 when Apple can't apply a gain table for the file, or it isn't RAW.
    public let exposureAnchorStops: Double
    public var size: CGSize { image.extent.size }

    init(image: CIImage, contract: InputContract, exposureAnchorStops: Double = 0) {
        self.image = image
        self.contract = contract
        self.exposureAnchorStops = exposureAnchorStops
    }
}

/// Turns camera data into linear light for the film system. RAW (ProRAW or Bayer DNG) goes
/// through Apple's CIRAWFilter with its rendering bypassed, so highlights keep their headroom
/// above 1.0. Display-referred photos only get an estimate of scene light from the neutral
/// film curve: the camera's rendering can't be undone.
public struct Developer {
    private let kernels: Kernels
    /// The exposure anchor's own context, caching intermediates (see `ExposureAnchor.stops(of:context:)`).
    private let context: CIContext

    init(kernels: Kernels, context: CIContext) {
        self.kernels = kernels
        self.context = context
    }

    public static func isRAW(_ data: Data) -> Bool { rawTypeIdentifier(of: data) != nil }

    static let dngTypeIdentifier = "com.adobe.raw-image"

    /// The RAW type of `data`, or nil when it isn't RAW. Read from memory, ImageIO types many
    /// DNGs as plain TIFF (23 of 25 ProRAW files tested, MOV-79) and CIRAWFilter then decodes
    /// them as TIFF too (BaselineExposure ignored, values capped at 1.0), so a file that isn't
    /// RAW on its own is asked again with a DNG hint. A plain TIFF keeps its type under the hint.
    private static func rawTypeIdentifier(of data: Data) -> String? {
        func type(hint: CFDictionary?) -> String? {
            guard let source = CGImageSourceCreateWithData(data as CFData, hint),
                let type = CGImageSourceGetType(source) as String?, UTType(type)?.conforms(to: .rawImage) == true
            else { return nil }
            return type
        }
        return type(hint: nil) ?? type(hint: [kCGImageSourceTypeIdentifierHint: dngTypeIdentifier] as CFDictionary)
    }

    /// `maxDimension` develops a smaller image for fast previews. RAW files whose DNG profile
    /// brightens through a gain table get the same `exposureAnchorStops` at any size.
    public func develop(_ data: Data, maxDimension: CGFloat? = nil) throws -> Negative {
        try develop(data, maxDimension: maxDimension, anchorsExposure: true)
    }

    /// `anchorsExposure: false` skips the exposure anchor, for tests and timings.
    func develop(_ data: Data, maxDimension: CGFloat?, anchorsExposure: Bool) throws -> Negative {
        if let type = Self.rawTypeIdentifier(of: data), let raw = CIRAWFilter(imageData: data, identifierHint: type) {
            Self.bypassAppleRendering(raw)
            // isLocalToneMapSupported: Apple can apply a gain table (ProfileGainTableMap) for this
            // file. Deliberately excluded, anchor 0: a DNG with a tone curve but no gain table, and
            // non-DNG RAW, where Apple's boost is its own look curve rather than the file's profile.
            let anchors = anchorsExposure && raw.isLocalToneMapSupported
            var anchorStops = 0.0
            if anchors {
                Self.applyPreviewScale(raw, maxDimension: ExposureAnchor.thumbnailLongEdge, allowsDraftMode: false)
                anchorStops = ExposureAnchor.stops(of: raw, context: context)
            }
            // Draft mode stays off after the anchor: switching it on decodes the file again.
            Self.applyPreviewScale(raw, maxDimension: maxDimension, allowsDraftMode: !anchors)
            guard var output = raw.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else {
                throw EmulsionError.unsupportedPhoto
            }
            if anchorStops != 0 {
                output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: anchorStops])
            }
            return Negative(image: Self.normalized(output), contract: .sceneReferred, exposureAnchorStops: anchorStops)
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
        return try sceneFromDisplay(Self.normalized(image))
    }

    /// Decodes at most `maxDimension` on the long edge (nil: full size), in RAW draft mode when
    /// that's smaller and `allowsDraftMode`.
    static func applyPreviewScale(_ raw: CIRAWFilter, maxDimension: CGFloat?, allowsDraftMode: Bool) {
        let native = raw.nativeSize
        let scale = maxDimension.map { min(1, $0 / max(native.width, native.height)) } ?? 1
        raw.scaleFactor = Float(scale)
        raw.isDraftModeEnabled = allowsDraftMode && scale < 1
    }

    /// Bypass Apple's rendering: no tone boost, local tone mapping, extra contrast, gamut
    /// mapping or shadow bias. What remains is demosaiced, white-balanced, linear scene light
    /// scaled by the file's BaselineExposure (the exposure anchor comes after); noise reduction,
    /// sharpening, lens correction and the decoder version stay at the file's defaults. Measured
    /// on synthetic DNGs and 25 real files (MOV-79, `RAWDevelopTests`).
    private static func bypassAppleRendering(_ raw: CIRAWFilter) {
        raw.boostAmount = 0
        // 1 is neutral (below 1 darkens the shadows; the file default is 0.9). It has no effect
        // while boost is 0 (pixel-identical develop, MOV-134) and only matters for the exposure
        // anchor's profile render. Set once, so the anchor's two thumbnails share one decode.
        raw.boostShadowAmount = 1
        if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
        if raw.isContrastSupported { raw.contrastAmount = 0 }
        // EDR 1–2 re-expands ProRAW highlights non-linearly and shifts midtones; 0 keeps them linear.
        raw.extendedDynamicRangeAmount = 0
        // Apple's gamut mapping clips highlights near 1.0 and pulls saturated colours inward;
        // without it out-of-gamut colours stay negative for the film model to handle.
        raw.isGamutMappingEnabled = false
        // A rendering default of 5 on cameras Apple has no profile for (bends the shadows); 0 on iPhone ProRAW.
        raw.shadowBias = 0
        // Clipped channels are estimated from unclipped ones so blown highlights stay neutral:
        // an estimate, not measured light.
        if raw.isHighlightRecoverySupported { raw.isHighlightRecoveryEnabled = true }
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

    /// Crops to whole pixels and moves the origin to (0, 0).
    static func normalized(_ image: CIImage) -> CIImage {
        let e = image.extent.integral
        return image.cropped(to: e).transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }
}
