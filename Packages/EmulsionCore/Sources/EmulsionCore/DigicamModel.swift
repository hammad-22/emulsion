import Foundation
import simd

/// The pointwise part of the digicam process for one edit: vignette, white balance, exposure, sensor
/// clip, saturation and the JPEG tone curve. `render` is the Swift mirror of the `digicamCapture`
/// kernel (Digicam.ci.metal) without noise and lens softness; the kernel arguments are packed from
/// the same values.
struct DigicamModel {
    /// White balance × 2^exposure, linear sRGB channel gains.
    let gains: SIMD3<Double>
    let saturation: Double
    /// Corner falloff, stops: `DigicamLook.vignetteStops` × the processing amount.
    let vignetteStops: Double

    /// `asShotTemperature`: the RAW file's as-shot white balance (kelvin), nil for photos that aren't RAW.
    init(_ a: Adjustments, asShotTemperature: Double?) {
        gains = Self.whiteBalanceGains(asShotTemperature: asShotTemperature, warmth: a.warmth, tint: a.tint) * pow(2, a.exposure)
        saturation = DigicamLook.saturation * (1 + a.color * (a.color >= 0 ? DigicamLook.colorBoost : DigicamLook.colorCut))
        vignetteStops = DigicamLook.vignetteStops * a.halation
    }

    /// Scene light (linear sRGB) at `radiusSquared` (0 at the centre, 1 at the corners) → display
    /// light (display-linear sRGB, 0…1).
    func render(_ scene: SIMD3<Double>, radiusSquared r2: Double = 0) -> SIMD3<Double> {
        let clip = DigicamLook.clip
        let black = DigicamLook.blackOffset
        let lit = scene * pow(2, -vignetteStops * r2) * gains
        var x = simd_max((simd_min(lit, SIMD3(repeating: clip)) / clip - black) / (1 - black), .zero)
        let y = Self.luma(x)
        x = simd_clamp(y + (x - y) * saturation, .zero, .one)
        return SIMD3(Self.toneCurve(x.x), Self.toneCurve(x.y), Self.toneCurve(x.z))
    }

    /// Light / clip (0…1) → display-linear value: sRGB encode, the mid-gray power, the S curve (a
    /// square on each side of the pivot) blended in by `contrast`, then the lifted black floor.
    static func toneCurve(_ x: Double) -> Double {
        let p = DigicamLook.toneCurvePivot
        let t = pow(ColorMath.encodeSRGB(min(max(x, 0), 1)), DigicamLook.gammaPower)
        let (lo, hi) = (t / p, (1 - t) / (1 - p))
        let s = t < p ? p * lo * lo : 1 - (1 - p) * hi * hi
        let v = t + (s - t) * DigicamLook.contrast
        let floor = DigicamLook.blackFloorCode
        return ColorMath.decode(floor + (1 - floor) * v, curve: srgbCurve)
    }

    // MARK: White balance

    /// Von Kries channel gains (linear sRGB, luminance 1) for what the simulated camera leaves of
    /// the light: its auto white balance corrects only `whiteBalanceCorrection` of the distance in
    /// mireds from `whiteBalanceReference` to the as-shot light, plus the constant cool-magenta bias
    /// and the user's Warmth and Tint. The develop has already neutralised the light, so the gains
    /// are light ÷ the camera's white.
    static func whiteBalanceGains(asShotTemperature: Double?, warmth: Double, tint: Double) -> SIMD3<Double> {
        let reference = 1e6 / DigicamLook.whiteBalanceReference
        let light = asShotTemperature.map { 1e6 / $0 } ?? reference
        let cameraWhite =
            reference + DigicamLook.whiteBalanceCorrection * (light - reference) + DigicamLook.biasMireds - warmth
            * DigicamLook.warmthMireds
        var gains = planckianSRGB(kelvin: 1e6 / light) / planckianSRGB(kelvin: 1e6 / cameraWhite)
        gains.y *= 1 - DigicamLook.biasMagenta - tint * DigicamLook.tintGreen
        return gains / luma(gains)
    }

    /// Linear sRGB of the Planckian radiator at `kelvin` (Y = 1).
    static func planckianSRGB(kelvin: Double) -> SIMD3<Double> {
        ColorMath.xyzToLinearSRGB * ColorMath.xyz(ColorMath.planckianChromaticity(kelvin: kelvin))
    }

    // MARK: Encoding

    /// The sRGB transfer function's curve in `ColorMath.decode` (Display P3 shares it).
    private static let srgbCurve = InputColorSpace.displayP3.curve

    static func luma(_ rgb: SIMD3<Double>) -> Double { (rgb * SIMD3(0.2126, 0.7152, 0.0722)).sum() }
}
