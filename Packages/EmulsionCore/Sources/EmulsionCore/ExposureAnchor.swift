import CoreImage
import Foundation

/// Stops that put the DNG profile's mid-gray at scene 0.18 (MOV-134; docs/CONSTANTS.md).
enum ExposureAnchor {
    enum Choice {
        case measured
        case known(stops: Double)
        case none
    }

    /// Fixed, so previews and exports get the same anchor.
    static let thumbnailLongEdge: CGFloat = 256
    private static let midGray = 0.18
    private static let windowStops = 1.0
    private static let minimumWindowShare = 0.01
    private static let luminanceFloor = 1e-6
    /// Measured −0.56…+2.95 stops on 25 real DNGs; the clamp only guards broken profiles.
    static let range = -2.0...5.0

    /// Needs Apple's rendering bypassed and draft mode off; `context` must cache intermediates.
    static func stops(of raw: CIRAWFilter, context: CIContext) -> Double {
        let linear = pixels(raw.outputImage, context: context)
        // Only these two: changing boostShadowAmount or contrastAmount too forces a new decode.
        raw.localToneMapAmount = 1
        raw.boostAmount = 1
        let profile = pixels(raw.outputImage, context: context)
        raw.localToneMapAmount = 0
        raw.boostAmount = 0
        context.clearCaches()
        return stops(linear: linear, profile: profile)
    }

    /// log2 of the geometric mean of Y(profile) ÷ Y(linear) over the mid-gray window, clamped.
    static func stops(linear: [SIMD4<Float>], profile: [SIMD4<Float>]) -> Double {
        guard linear.count == profile.count else { return 0 }
        let window = (midGray * pow(2, -windowStops))...(midGray * pow(2, windowStops))
        var windowSum = 0.0
        var windowCount = 0
        var allSum = 0.0
        var allCount = 0
        for (a, p) in zip(linear, profile) {
            let ya = luminance(a)
            let yp = luminance(p)
            guard ya > luminanceFloor, yp > luminanceFloor, ya.isFinite, yp.isFinite else { continue }
            let ratio = log2(yp / ya)
            allSum += ratio
            allCount += 1
            if window.contains(yp) {
                windowSum += ratio
                windowCount += 1
            }
        }
        guard allCount > 0 else { return 0 }
        let useWindow = Double(windowCount) >= minimumWindowShare * Double(allCount)
        let mean = useWindow ? windowSum / Double(windowCount) : allSum / Double(allCount)
        return min(max(mean, range.lowerBound), range.upperBound)
    }

    private static func luminance(_ c: SIMD4<Float>) -> Double {
        let (kr, kb) = YCbCrMatrix.bt709.weights
        return kr * Double(c.x) + (1 - kr - kb) * Double(c.y) + kb * Double(c.z)
    }

    /// Float readback, so values above 1 and below 0 survive.
    private static func pixels(_ image: CIImage?, context: CIContext) -> [SIMD4<Float>] {
        guard let image, !image.extent.isEmpty, !image.extent.isInfinite else { return [] }
        let bounds = image.extent.integral
        let width = Int(bounds.width)
        var pixels = [SIMD4<Float>](repeating: .zero, count: width * Int(bounds.height))
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                image, toBitmap: base, rowBytes: width * MemoryLayout<SIMD4<Float>>.stride, bounds: bounds, format: .RGBAf,
                colorSpace: Renderer.workingSpace)
        }
        return pixels
    }
}
