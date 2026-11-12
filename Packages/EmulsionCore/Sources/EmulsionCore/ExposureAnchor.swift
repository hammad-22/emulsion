import CoreImage
import Foundation

/// The exposure anchor (MOV-134): stops added to a RAW develop so that the tones the file's own
/// DNG profile (ProfileGainTableMap and ProfileToneCurve) renders at mid-gray sit at scene 0.18.
/// 48 MP ProRAW carries 2–3 stops of its brightening in the gain table, which the linear develop
/// bypasses. The anchor is an estimate that follows the profile, not a measurement of the scene.
enum ExposureAnchor {
    /// How a develop gets its anchor: measured from the file, a value already known for it, or
    /// none (tests and timings).
    enum Choice {
        case measured
        case known(stops: Double)
        case none
    }

    /// Long edge of the two thumbnails compared. Fixed, so previews and exports get the same anchor.
    static let thumbnailLongEdge: CGFloat = 256
    private static let midGray = 0.18
    /// Pixels whose profile render is within ±1 stop of mid-gray choose the anchor.
    private static let windowStops = 1.0
    /// Below this share of valid pixels in the window, every valid pixel counts instead.
    private static let minimumWindowShare = 0.01
    /// Luminance at or below this has no usable ratio.
    private static let luminanceFloor = 1e-6
    /// Measured −0.56…+2.95 stops on 25 real DNGs; the clamp only stops a broken profile or a
    /// near-black frame from throwing the develop far off.
    static let range = -2.0...5.0

    /// The anchor of `raw`, which needs Apple's rendering bypassed, the thumbnail scale set and
    /// draft mode off. Leaves local tone map and boost back at 0.
    /// `context` caches intermediates, so the profile render reuses the linear render's decode:
    /// Apple's own reuse between renders of one filter depends on what the process decoded
    /// before (on the iPhone 14 Pro, 12 Pro and Pixel files every render could decode again, MOV-134).
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

    /// log2 of the geometric mean of Y(profile) / Y(linear) over the pixels whose profile
    /// luminance is within `windowStops` of mid-gray, clamped to `range`; 0 when no pixel has
    /// a usable ratio or the renders differ in size. Pixels are linear sRGB RGBA (alpha ignored),
    /// the same pixel at the same index in both.
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

    /// Rec. 709 luminance of linear sRGB.
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
