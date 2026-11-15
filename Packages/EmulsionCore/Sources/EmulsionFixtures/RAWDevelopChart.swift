import Foundation
import simd

/// The RAW develop chart (MOV-79): a half-stop neutral wedge, then chromatic patches (docs).
public enum RAWDevelopChart {
    static let linearSRGBFromP3 =
        SyntheticDNG.xyzFromLinearSRGB.inverse
        * simd_double3x3(rows: [
            SIMD3(0.4865709, 0.2656677, 0.1982173),
            SIMD3(0.2289746, 0.6917385, 0.0792869),
            SIMD3(0.0000000, 0.0451134, 1.0439444),
        ])

    public static let midGray = 0.18
    /// With the default camera the top three patches clip green at the sensor.
    public static let wedgeStops = Array(stride(from: -4.0, through: 3.5, by: 0.5))
    /// P3 red at 0.9 and a saturated green: negative in linear sRGB.
    public static let outOfSRGBP3: [SIMD3<Double>] = [[0.9, 0, 0], [0.05, 0.8, 0.1]]
    public static let chromaticScene: [SIMD3<Double>] =
        SceneFixtures.patchesP3.prefix(6).map { linearSRGBFromP3 * SIMD3<Double>($0) }
        + outOfSRGBP3.map { linearSRGBFromP3 * $0 }
    static let neutralScene = wedgeStops.map { SIMD3(repeating: midGray * pow(2, $0)) }
    public static let scene = neutralScene + chromaticScene
    public static let neutralIndices = neutralScene.indices
    public static let chromaticIndices = neutralScene.count..<scene.count
    public static let outOfSRGBIndices = (scene.count - outOfSRGBP3.count)..<scene.count
    public static let camera = SyntheticDNG.wideGamutCameraFromXYZ

    public static func chart(cell: Int = 48) -> PatchChart { PatchChart(scene, cell: cell) }

    public static func cameraValues(_ scene: [SIMD3<Double>], cameraFromXYZ: simd_double3x3 = camera) -> [SIMD3<Double>] {
        scene.map { SyntheticDNG.camera(linearSRGB: $0, cameraFromXYZ: cameraFromXYZ) }
    }

    /// Camera values under `light` instead of D65: von Kries in camera space, exact for neutrals.
    public static func cameraValues(_ scene: [SIMD3<Double>], light: SIMD2<Double>) -> [SIMD3<Double>] {
        let lightRatio =
            SyntheticDNG.camera(chromaticity: light, cameraFromXYZ: camera)
            / SyntheticDNG.camera(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: camera)
        return cameraValues(scene).map { $0 * lightRatio }
    }

    /// A DNG of `chart` lit by `light`, its AsShotNeutral set for `taggedLight`.
    public static func dng(
        _ mosaic: SyntheticDNG.Mosaic, chart: PatchChart, light: SIMD2<Double> = SyntheticDNG.d65Chromaticity,
        taggedLight: SIMD2<Double> = SyntheticDNG.d65Chromaticity, baselineStops: Double = 0, profile: SyntheticDNG.Profile? = nil
    ) -> Data {
        let sensor = PatchChart(cameraValues(chart.patches, light: light), cell: chart.cell, columns: chart.columns)
        return SyntheticDNG(
            mosaic: mosaic, width: chart.width, height: chart.height, baselineExposureStops: baselineStops,
            asShotNeutral: SyntheticDNG.neutral(chromaticity: taggedLight, cameraFromXYZ: camera), cameraFromXYZ: camera,
            profile: profile
        ).data { sensor.value(x: $0, y: $1) }
    }
}
