import Foundation
import simd

/// The pointwise part of the digicam process for one edit: white balance, exposure, sensor clip,
/// saturation and the JPEG tone curve. `render` is the Swift mirror of the `digicamCapture` kernel
/// (Digicam.ci.metal) without noise, corner softness and fringing; the kernel arguments are packed
/// from the same values.
struct DigicamModel {
    /// White balance × 2^exposure, linear sRGB channel gains.
    let gains: SIMD3<Double>
    /// Scene light that clips, after the gains.
    let clip: Double
    let saturation: Double
    /// Power on the sRGB-encoded value that puts mid-gray on `DigicamLook.middleGrayCode`.
    let gammaPower: Double

    /// `asShotTemperature`: the RAW file's as-shot white balance (kelvin), nil for photos that aren't RAW.
    init(_ a: Adjustments, asShotTemperature: Double?) {
        gains = Self.whiteBalanceGains(asShotTemperature: asShotTemperature, warmth: a.warmth, tint: a.tint) * pow(2, a.exposure)
        clip = 0.18 * pow(2, DigicamLook.clipStops)
        saturation = DigicamLook.saturation * (1 + a.color * (a.color >= 0 ? DigicamLook.colorBoost : DigicamLook.colorCut))
        let middleGray = max(0.18 / clip - DigicamLook.blackOffset, 0) / (1 - DigicamLook.blackOffset)
        gammaPower = log(DigicamLook.middleGrayCode) / log(Self.encode(middleGray))
    }

    /// Scene light (linear sRGB) at `radiusSquared` (0 at the centre, 1 at the corners) → display
    /// light (display-linear sRGB, 0…1).
    func render(_ scene: SIMD3<Double>, radiusSquared r2: Double = 0) -> SIMD3<Double> {
        let lit = scene * pow(2, -DigicamLook.vignetteStops * r2) * gains
        var x = (simd_min(lit, SIMD3(repeating: clip)) / clip - DigicamLook.blackOffset) / (1 - DigicamLook.blackOffset)
        x = simd_max(x, .zero)
        let y = Self.luma(x)
        x = simd_clamp(y + (x - y) * saturation, .zero, .one)
        return SIMD3(toneCurve(x.x), toneCurve(x.y), toneCurve(x.z))
    }

    /// Light / clip (0…1) → display-linear value.
    func toneCurve(_ x: Double) -> Double {
        let pivot = DigicamLook.middleGrayCode
        let power = DigicamLook.contrastPower
        let t = pow(Self.encode(min(max(x, 0), 1)), gammaPower)
        let s = t < pivot ? pivot * pow(t / pivot, power) : 1 - (1 - pivot) * pow((1 - t) / (1 - pivot), power)
        return Self.decode(t + (s - t) * DigicamLook.contrast)
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

    /// Linear sRGB of the Planckian radiator at `kelvin` (Y = 1), from the chromaticity
    /// approximation of Kim et al. 2002 (valid 1667–25000 K; clamped to it).
    static func planckianSRGB(kelvin: Double) -> SIMD3<Double> {
        let t = min(max(kelvin, 1667), 25000)
        let (t1, t2, t3) = (1e3 / t, 1e6 / (t * t), 1e9 / (t * t * t))
        let x =
            t <= 4000
            ? -0.2661239 * t3 - 0.2343589 * t2 + 0.8776956 * t1 + 0.179910
            : -3.0258469 * t3 + 2.1070379 * t2 + 0.2226347 * t1 + 0.240390
        let y: Double =
            switch t {
            case ..<2222: -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
            case ..<4000: -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
            default: 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
            }
        let xyz = SIMD3(x / y, 1, (1 - x - y) / y)
        // XYZ → linear sRGB (IEC 61966-2-1, D65).
        return SIMD3(
            (SIMD3(3.2404542, -1.5371385, -0.4985314) * xyz).sum(), (SIMD3(-0.9692660, 1.8760108, 0.0415560) * xyz).sum(),
            (SIMD3(0.0556434, -0.2040259, 1.0572252) * xyz).sum())
    }

    // MARK: Encoding

    static func luma(_ rgb: SIMD3<Double>) -> Double { (rgb * SIMD3(0.2126, 0.7152, 0.0722)).sum() }
    /// sRGB transfer function (IEC 61966-2-1) and its inverse.
    static func encode(_ x: Double) -> Double { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
    static func decode(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
}
