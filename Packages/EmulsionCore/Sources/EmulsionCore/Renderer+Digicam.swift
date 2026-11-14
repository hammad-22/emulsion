import CoreImage
import Foundation

/// The digicam process: a mid-2000s compact CCD camera's in-camera JPEG, not a film process.
/// Scene light is cropped to the sensor's 4:3 frame and capped at its size, passes a cheap lens
/// (vignette, soft corners, purple fringing), the camera's partial auto white balance, a noisy
/// sensor that clips hard per channel, saturation and a JPEG tone curve, then the in-camera
/// sharpening and, at sensor size, a real JPEG encode. Constants are in `DigicamLook`.
extension Renderer {
    func renderDigicam(_ negative: Negative, _ a: Adjustments) throws -> CIImage {
        let scene = Self.sensorFrame(negative.image)
        let extent = scene.extent
        let longEdge = max(extent.width, extent.height)
        // Spatial sizes are in sensor pixels, so a preview is close to a downscale of the export.
        let pixelsPerSensorPixel = longEdge / DigicamLook.sensorLongEdge
        let model = DigicamModel(a, asShotTemperature: negative.asShotWhiteBalance?.temperature)
        let processing = a.halation
        let k = digicamKernels

        let soft = Self.blurred(scene, sigma: DigicamLook.cornerSoftnessSigma * pixelsPerSensorPixel)
        // Without processing the mask and its blur are the scene itself, so the fringe is zero.
        var mask = scene
        var maskBlur = scene
        // The channel with the largest gain clips first.
        let clipsAt = model.clip / model.gains.max()
        if processing > 0 {
            mask = try kernels.run(k.fringeSource, extent, [scene, CIVector(x: clipsAt, y: DigicamLook.fringeOnset)])
            maskBlur = Self.blurred(mask, sigma: DigicamLook.fringeRadius * pixelsPerSensorPixel)
        }
        let fringe = DigicamLook.fringeColor * (DigicamLook.fringeStrength * processing * clipsAt)
        let halfDiagonalSquared = (extent.width * extent.width + extent.height * extent.height) / 4
        let lens = CIVector(x: extent.midX, y: extent.midY, z: 1 / halfDiagonalSquared, w: DigicamLook.vignetteStops)
        let noise = CIVector(
            x: a.grain, y: pixelsPerSensorPixel, z: DigicamLook.chromaNoiseCell * pixelsPerSensorPixel, w: a.seed)
        let noiseShape = CIVector(x: DigicamLook.shotNoise, y: DigicamLook.readNoise, z: DigicamLook.chromaNoiseShare, w: 0)
        let tone = CIVector(x: model.saturation, y: model.gammaPower, z: DigicamLook.contrast, w: DigicamLook.blackOffset)
        let curve = CIVector(x: DigicamLook.middleGrayCode, y: DigicamLook.contrastPower, z: 0, w: 0)
        var image = try kernels.run(
            k.capture, extent,
            [
                scene, soft, mask, maskBlur, lens, CIVector(x: fringe.x, y: fringe.y, z: fringe.z, w: 0),
                CIVector(x: model.gains.x, y: model.gains.y, z: model.gains.z, w: model.clip), noise, noiseShape, tone, curve,
            ])

        if a.highlights != 0 || a.shadows != 0 {
            image = try kernels.applyLocalTone(image, shadows: a.shadows, highlights: a.highlights)
        }
        if processing > 0 {
            let luma = try kernels.run(k.encodedLuma, extent, [image])
            let blurredLuma = Self.blurred(luma, sigma: DigicamLook.sharpenRadius * pixelsPerSensorPixel)
            image = try kernels.run(k.sharpen, extent, [image, blurredLuma, DigicamLook.sharpenAmount * processing])
        }
        // At preview sizes the 8×8 JPEG blocks would be sub-pixel, so only a render at sensor size
        // (an export of a photo at least that large) goes through the encoder.
        if processing > 0 && longEdge == DigicamLook.sensorLongEdge {
            image = try jpegRoundTrip(image.cropped(to: extent), quality: DigicamLook.jpegQuality)
        }
        return image.cropped(to: extent)
    }

    /// The source centre-cropped to 4:3 (landscape or portrait, as the source), moved to the origin,
    /// and Lanczos-downscaled when its long edge exceeds the sensor's.
    static func sensorFrame(_ image: CIImage) -> CIImage {
        let source = image.extent
        let long = max(source.width, source.height)
        let short = min(source.width, source.height)
        let aspect = DigicamLook.aspectRatio
        let (cropLong, cropShort) =
            long / short > aspect ? ((short * aspect).rounded(.down), short) : (long, (long / aspect).rounded(.down))
        let size = source.width >= source.height ? CGSize(width: cropLong, height: cropShort) : CGSize(width: cropShort, height: cropLong)
        let origin = CGPoint(
            x: source.minX + ((source.width - size.width) / 2).rounded(.down),
            y: source.minY + ((source.height - size.height) / 2).rounded(.down))
        let frame = image.cropped(to: CGRect(origin: origin, size: size))
            .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        let scale = DigicamLook.sensorLongEdge / max(size.width, size.height)
        guard scale < 1 else { return frame }
        let output = CGRect(x: 0, y: 0, width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        // Clamped first so the edge pixels don't blend with transparency.
        return frame.clampedToExtent().lanczosScaled(by: scale).cropped(to: output)
    }

    /// A Gaussian blur of the image's own extent, edges extended.
    private static func blurred(_ image: CIImage, sigma: Double) -> CIImage {
        image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
    }

    /// Display light through a real JPEG encode and decode (sRGB, Core Image's encoder), so the
    /// export carries the camera's compression.
    private func jpegRoundTrip(_ image: CIImage, quality: Double) throws -> CIImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        guard let data = context.jpegRepresentation(of: image, colorSpace: srgb, options: options),
            let decoded = CIImage(data: data)
        else { throw EmulsionError.renderFailed }
        return decoded
    }
}
