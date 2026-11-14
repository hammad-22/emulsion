import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

extension RAWDevelopProbe {
    static let tungstenKelvin = 2856.0

    /// CIE daylight xy, CIE 15:2004 eq. 3.3–3.4; defined for 4000–25000 K only.
    static func daylightChromaticity(kelvin t: Double) -> SIMD2<Double>? {
        guard (4000...25000).contains(t) else { return nil }
        let t3 = t * t * t
        let x =
            t <= 7000
            ? -4.6070e9 / t3 + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
            : -2.0064e9 / t3 + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
        return SIMD2(x, -3.000 * x * x + 2.870 * x - 0.275)
    }

    static func grayLine(_ rgb: SIMD3<Double>) -> String {
        let neutral = SIMD3(repeating: RAWDevelopSupport.luminance(rgb))
        let dE = Fixtures.deltaE(Fixtures.toOKLab(rgb), Fixtures.toOKLab(neutral))
        return "gray \(pad(rgb.fourDigits, 32)) R/G \((rgb.x / rgb.y).fourDigits) B/G \((rgb.z / rgb.y).fourDigits)"
            + " max|.-1| \(RAWDevelopSupport.neutralError(rgb).fourDigits) dE(OKLab x100) \(dE.fourDigits)"
    }

    @Test func whiteBalance() throws {
        let scene = [SIMD3(repeating: RAWDevelopChart.midGray)] + RAWDevelopChart.chromaticScene.prefix(6)
        let chart = PatchChart(scene, cell: 64)
        let tungstenXY = SyntheticDNG.planckianChromaticity(kelvin: Self.tungstenKelvin)
        let temperatures = [2500.0, 3200, 4000, 5000, 6500, 8000, 10000]
        print(
            "\n#### RAW probe: white balance. Planckian \(Self.tungstenKelvin) K xy=\(tungstenXY) (Kim et al. 2002); D65 xy=\(SyntheticDNG.d65Chromaticity)"
        )
        for (cameraName, cm) in [("wide-gamut camera", RAWDevelopChart.camera), ("sRGB camera", SyntheticDNG.sRGBCameraFromXYZ)] {
            let d65Camera = SyntheticDNG.camera(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: cm)
            let tungstenCamera = SyntheticDNG.camera(chromaticity: tungstenXY, cameraFromXYZ: cm)
            let lightRatio = tungstenCamera / d65Camera
            let underD65 = RAWDevelopChart.cameraValues(scene, cameraFromXYZ: cm)
            let underTungsten = underD65.map { $0 * lightRatio }
            let tungstenNeutral = SyntheticDNG.neutral(chromaticity: tungstenXY, cameraFromXYZ: cm)
            let d65Neutral = SyntheticDNG.neutral(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: cm)
            print("\n== \(cameraName): neutral(2856 K)=\(tungstenNeutral.fourDigits) neutral(D65)=\(d65Neutral.fourDigits)")
            for t in temperatures {
                let p = SyntheticDNG.planckianChromaticity(kelvin: t)
                let d = Self.daylightChromaticity(kelvin: t)
                print(
                    "  T=\(Int(t)) Planck xy=(\(p.x.fourDigits), \(p.y.fourDigits)) neutral \(SyntheticDNG.neutral(chromaticity: p, cameraFromXYZ: cm).fourDigits)"
                        + " daylight xy=\(d.map { "(\($0.x.fourDigits), \($0.y.fourDigits))" } ?? "undefined <4000 K")")
            }
            for mosaic in SyntheticDNG.Mosaic.allCases {
                func file(_ cameras: [SIMD3<Double>], neutral: SIMD3<Double>) -> Data {
                    let sensor = PatchChart(cameras, cell: chart.cell, columns: chart.columns)
                    return SyntheticDNG(mosaic: mosaic, width: chart.width, height: chart.height, asShotNeutral: neutral, cameraFromXYZ: cm)
                        .data { sensor.value(x: $0, y: $1) }
                }
                let correct = file(underTungsten, neutral: tungstenNeutral)
                let wrong = file(underTungsten, neutral: d65Neutral)
                let daylight = file(underD65, neutral: d65Neutral)

                func gray(_ data: Data, _ configure: (CIRAWFilter) -> Void = { _ in }) throws -> (rgb: SIMD3<Double>, raw: CIRAWFilter) {
                    let raw = try RAWDevelopSupport.filter(data)
                    RAWDevelopSupport.applyPreMOV79Develop(raw)
                    configure(raw)
                    return (Self.means(try #require(Self.read(raw)), chart: chart)[0], raw)
                }
                print("\n -- \(cameraName) \(mosaic)")
                for (name, data) in [
                    ("2856 K scene, correctly tagged", correct), ("2856 K scene, tagged D65", wrong), ("D65 scene, tagged D65", daylight),
                ] {
                    let raw = try RAWDevelopSupport.filter(data)
                    print(
                        "  \(Self.pad(name, 32)) as-shot temp=\(raw.neutralTemperature) tint=\(raw.neutralTint) xy=\(raw.neutralChromaticity) | \(Self.grayLine(try gray(data).rgb))"
                    )
                }
                print("  wrongly tagged file:")
                let cases: [(String, (CIRAWFilter) -> Void)] = [
                    ("as shot", { _ in }),
                    (
                        "temp 2856 tint 0",
                        {
                            $0.neutralTemperature = Float(Self.tungstenKelvin)
                            $0.neutralTint = 0
                        }
                    ),
                    ("neutralChromaticity = Planck 2856 xy", { $0.neutralChromaticity = CGPoint(x: tungstenXY.x, y: tungstenXY.y) }),
                ]
                for (label, configure) in cases {
                    let (rgb, raw) = try gray(wrong, configure)
                    print(
                        "    \(Self.pad(label, 40)) read back temp=\(raw.neutralTemperature) tint=\(raw.neutralTint) | \(Self.grayLine(rgb))"
                    )
                }
                print("  temperature sweep, tint 0 (wrongly tagged file):")
                for t in temperatures.map(Float.init) {
                    let (rgb, raw) = try gray(wrong) {
                        $0.neutralTemperature = t
                        $0.neutralTint = 0
                    }
                    print("    T=\(Int(t)) read back \(raw.neutralTemperature)/\(raw.neutralTint) | \(Self.grayLine(rgb))")
                }
                let tints = try [Float(-50), 0, 50].map { tint in
                    let (rgb, raw) = try gray(wrong) {
                        $0.neutralTemperature = 6500
                        $0.neutralTint = tint
                    }
                    return "\(Int(tint)) (read \(raw.neutralTint)): R/G \((rgb.x / rgb.y).fourDigits) B/G \((rgb.z / rgb.y).fourDigits)"
                }
                print("  tint sweep at 6500 K: " + tints.joined(separator: "; "))
            }
        }
    }
}
