import Foundation
import simd

/// Swift mirror of the `digicamCapture` kernel without noise and lens softness; see docs/DIGICAM.md.
struct DigicamModel {
    /// White balance × 2^exposure, linear sRGB channel gains.
    let gains: SIMD3<Double>
    let saturation: Double
    let vignetteStops: Double

    init(_ a: Adjustments, asShotTemperature: Double?) {
        gains = Self.whiteBalanceGains(asShotTemperature: asShotTemperature, warmth: a.warmth, tint: a.tint) * pow(2, a.exposure)
        saturation = DigicamLook.saturation * (1 + a.color * (a.color >= 0 ? DigicamLook.colorBoost : DigicamLook.colorCut))
        vignetteStops = DigicamLook.vignetteStops * a.halation
    }

    /// Scene light (linear sRGB) → display-linear sRGB; `radiusSquared` is 1 at the corners.
    func render(_ scene: SIMD3<Double>, radiusSquared r2: Double = 0) -> SIMD3<Double> {
        let clip = DigicamLook.clip
        let black = DigicamLook.blackOffset
        let lit = scene * pow(2, -vignetteStops * r2) * gains
        var x = simd_max((simd_min(lit, SIMD3(repeating: clip)) / clip - black) / (1 - black), .zero)
        let y = Self.luma(x)
        x = simd_clamp(y + (x - y) * saturation, .zero, .one)
        return SIMD3(Self.toneCurve(x.x), Self.toneCurve(x.y), Self.toneCurve(x.z))
    }

    /// Light ÷ clip (0…1) → display-linear value.
    static func toneCurve(_ x: Double) -> Double {
        let p = DigicamLook.toneCurvePivot
        let t = pow(ColorMath.encodeSRGB(min(max(x, 0), 1)), DigicamLook.gammaPower)
        let (lo, hi) = (t / p, (1 - t) / (1 - p))
        let s = t < p ? p * lo * lo : 1 - (1 - p) * hi * hi
        let v = t + (s - t) * DigicamLook.contrast
        let floor = DigicamLook.blackFloorCode
        return ColorMath.decode(floor + (1 - floor) * v, curve: .sRGB)
    }

    /// Von Kries gains for the light the simulated auto white balance leaves (docs/DIGICAM.md).
    static func whiteBalanceGains(asShotTemperature: Double?, warmth: Double, tint: Double) -> SIMD3<Double> {
        let reference = mireds(kelvin: DigicamLook.whiteBalanceReference)
        let light = asShotTemperature.map { mireds(kelvin: $0) } ?? reference
        let cameraWhite =
            reference + DigicamLook.whiteBalanceCorrection * (light - reference) + DigicamLook.biasMireds - warmth
            * DigicamLook.warmthMireds
        var gains = planckianSRGB(kelvin: kelvin(mireds: light)) / planckianSRGB(kelvin: kelvin(mireds: cameraWhite))
        gains.y *= 1 - DigicamLook.biasMagenta - tint * DigicamLook.tintGreen
        return gains / luma(gains)
    }

    static func planckianSRGB(kelvin: Double) -> SIMD3<Double> {
        ColorMath.xyzToLinearSRGB * ColorMath.xyz(ColorMath.planckianChromaticity(kelvin: kelvin))
    }

    private static func mireds(kelvin: Double) -> Double { 1e6 / kelvin }
    private static func kelvin(mireds: Double) -> Double { 1e6 / mireds }

    /// ITU-R BT.709 luma weights, as the kernel's `digicamLuma709`.
    private static let rec709LumaWeights = SIMD3(0.2126, 0.7152, 0.0722)

    static func luma(_ rgb: SIMD3<Double>) -> Double { (rgb * rec709LumaWeights).sum() }
}
