import CoreImage
import Foundation

/// Edge-aware Highlights/Shadows. Carried over from the GradingCore local-tone study, where it
/// measured ≤1 code of halo against 17–22 codes for CIHighlightShadowAdjust.
///
/// Base: perceptual lightness averaged over exact 16×16 blocks (padded grid, four 2×2
/// halvings), upsampled with CIEdgePreserveUpsampleFilter guided by full-resolution lightness.
/// The curve acts on the base; detail rides additively in lightness; one RGB ratio keeps hue.
public enum LocalTone {
    public static let shadowStrength = 2.2, shadowPivot = 0.55
    public static let highlightStrength = 2.2, highlightPivot = 0.45
    /// Negative settings (deepen shadows / brighten highlights) are scaled so the curve stays
    /// monotone: slope ≥ 1 − 0.4·2.2 > 0.
    static let negativeScale = 0.4
    static let block: CGFloat = 16
    static let spatialSigma = 1.0, lumaSigma = 0.01

    static func amount(_ x: Double) -> Double { x < 0 ? x * negativeScale : x }

    public static func baseCurve(_ lightness: Double, shadows: Double, highlights: Double) -> Double {
        let s = amount(shadows)
        let h = amount(highlights)
        let u = min(1, max(0, 1 - lightness / shadowPivot))
        let y = 1 - lightness
        let v = min(1, max(0, 1 - y / highlightPivot))
        return lightness + s * shadowStrength * lightness * u * u - h * highlightStrength * y * v * v
    }
}

extension Kernels {
    func applyLocalTone(_ image: CIImage, shadows: Double, highlights: Double) throws -> CIImage {
        let extent = image.extent
        let guide = try run(lightnessGuide, extent, [image])
        let curve = CIVector(
            x: LocalTone.shadowStrength, y: LocalTone.shadowPivot,
            z: LocalTone.highlightStrength, w: LocalTone.highlightPivot)
        let args: (CIImage) -> [Any] = { [image, $0, LocalTone.amount(shadows), LocalTone.amount(highlights), curve] }
        let b = LocalTone.block
        guard min(extent.width, extent.height) >= 2 * b else { return try run(localTone, extent, args(guide)) }
        let padded = CGRect(x: 0, y: 0, width: (extent.width / b).rounded(.up) * b, height: (extent.height / b).rounded(.up) * b)
        let origin = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        let paddedGuide = guide.transformed(by: origin).clampedToExtent().cropped(to: padded)
        var small = paddedGuide
        for _ in 0..<4 { small = small.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)) }
        let smallRect = CGRect(x: 0, y: 0, width: padded.width / b, height: padded.height / b)
        small = small.cropped(to: smallRect).clampedToExtent().cropped(to: smallRect)
        let base = paddedGuide.applyingFilter(
            "CIEdgePreserveUpsampleFilter",
            parameters: [
                "inputSmallImage": small, "inputSpatialSigma": LocalTone.spatialSigma, "inputLumaSigma": LocalTone.lumaSigma,
            ]
        )
        .cropped(to: CGRect(origin: .zero, size: extent.size)).transformed(by: origin.inverted())
        return try run(localTone, extent, args(base))
    }
}
