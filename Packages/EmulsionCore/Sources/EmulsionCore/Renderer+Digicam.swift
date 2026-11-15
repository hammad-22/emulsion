import CoreImage
import Foundation

/// The digicam process: a mid-2000s compact camera's in-camera JPEG (docs/DIGICAM.md).
extension Renderer {
    func renderDigicam(_ negative: Negative, _ a: Adjustments, intent: RenderIntent) throws -> CIImage {
        var scene = Self.sensorFrame(negative.image)
        let extent = scene.extent
        let pixelsPerSensorPixel = max(extent.width, extent.height) / DigicamLook.sensorLongEdge
        let model = DigicamModel(a, asShotTemperature: negative.asShotWhiteBalance?.temperature)
        let processing = a.halation
        let k = digicamKernels

        if processing > 0 {
            let clipsAt = DigicamLook.clip / model.gains.max()
            let mask = try kernels.run(k.fringeSource, extent, [scene, CIVector(x: clipsAt, y: DigicamLook.fringeOnset)])
            let maskBlur = Self.blurred(mask, sigma: DigicamLook.fringeRadius * pixelsPerSensorPixel)
            let fringe = DigicamLook.fringeColor * (DigicamLook.fringeStrength * processing * clipsAt)
            scene = try kernels.run(k.fringe, extent, [scene, mask, maskBlur, CIVector(x: fringe.x, y: fringe.y, z: fringe.z, w: 0)])
        }
        let cornerSigma = max(DigicamLook.lensSoftnessSigma, DigicamLook.cornerSoftnessSigma * processing)
        let corners = Self.blurred(scene, sigma: cornerSigma * pixelsPerSensorPixel)
        scene = Self.blurred(scene, sigma: DigicamLook.lensSoftnessSigma * pixelsPerSensorPixel)
        let halfDiagonalSquared = (extent.width * extent.width + extent.height * extent.height) / 4
        let lens = CIVector(x: extent.midX, y: extent.midY, z: 1 / halfDiagonalSquared, w: model.vignetteStops)
        let gains = CIVector(x: model.gains.x, y: model.gains.y, z: model.gains.z, w: DigicamLook.clip)
        let noise = CIVector(x: a.grain, y: pixelsPerSensorPixel, z: DigicamLook.chromaNoiseCell * pixelsPerSensorPixel, w: a.seed)
        let noiseShape = CIVector(
            x: DigicamLook.shotNoise, y: DigicamLook.readNoise, z: DigicamLook.chromaNoiseShare, w: DigicamLook.blueNoiseGain)
        let tone = CIVector(x: model.saturation, y: DigicamLook.gammaPower, z: DigicamLook.contrast, w: DigicamLook.blackOffset)
        let curve = CIVector(x: DigicamLook.toneCurvePivot, y: DigicamLook.blackFloorCode, z: 0, w: 0)
        var image = try kernels.run(k.capture, extent, [scene, corners, lens, gains, noise, noiseShape, tone, curve])

        if a.highlights != 0 || a.shadows != 0 {
            image = try kernels.applyLocalTone(image, shadows: a.shadows, highlights: a.highlights)
        }
        if processing > 0 {
            let luma = try kernels.run(k.encodedLuma, extent, [image])
            let blurredLuma = Self.blurred(luma, sigma: DigicamLook.sharpenRadius * pixelsPerSensorPixel)
            image = try kernels.run(k.sharpen, extent, [image, blurredLuma, DigicamLook.sharpenAmount * processing])
        }
        // Previews skip the encoder: at their size the 8×8 blocks would be sub-pixel.
        if intent == .export && processing > 0 {
            let quality = DigicamLook.jpegQualityClean - DigicamLook.jpegQualityLoss * processing
            image = try jpegRoundTrip(image.cropped(to: extent), quality: quality)
        }
        return image.cropped(to: extent)
    }

    /// Centre-cropped to 4:3, moved to the origin, and downscaled to the sensor size.
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

    private static func blurred(_ image: CIImage, sigma: Double) -> CIImage {
        guard sigma >= DigicamLook.minimumBlurSigma else { return image }
        return image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
    }

    private func jpegRoundTrip(_ image: CIImage, quality: Double) throws -> CIImage {
        guard let decoded = CIImage(data: try jpegData(image, colorSpace: Self.cameraSpace, quality: quality)) else {
            throw EmulsionError.renderFailed
        }
        return decoded
    }

    /// Period cameras wrote sRGB JPEGs.
    private static let cameraSpace = CGColorSpace(name: CGColorSpace.sRGB)!
}
