import CoreImage
import CoreVideo
import simd

extension simd_double3x3 {
    /// The three rows, as `simd_double3x3(rows:)` takes them (simd stores columns).
    var rows: [SIMD3<Double>] { (0..<3).map { r in SIMD3(self[0][r], self[1][r], self[2][r]) } }
}

extension CIVector {
    /// The matrix rows as kernel arguments (`w` unused).
    static func rows(of m: simd_double3x3) -> [CIVector] { m.rows.map { CIVector(x: $0.x, y: $0.y, z: $0.z, w: 0) } }
}

extension CIImage {
    func lanczosScaled(by scale: CGFloat) -> CIImage {
        applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
}

extension CIContext {
    /// `image` rendered once into a half-float buffer that the returned image reads; extended-range values are kept.
    func renderedToBuffer(_ image: CIImage, colorSpace: CGColorSpace) throws -> CIImage {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary
        let created = CVPixelBufferCreate(
            nil, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_64RGBAHalf, attributes, &buffer)
        guard created == kCVReturnSuccess, let buffer else { throw EmulsionError.renderFailed }
        defer { clearCaches() }
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.colorSpace = colorSpace
        // A render task reports a failed render, which `render(_:to:bounds:colorSpace:)` doesn't.
        try startTask(toRender: image, from: image.extent, to: destination, at: .zero).waitUntilCompleted()
        // Attached rather than passed as an option, which would hide the buffer from `CIImage.pixelBuffer`.
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return CIImage(cvPixelBuffer: buffer)
    }
}
