import Foundation
import simd

/// The scene and synthetic files used to measure RAW develop (MOV-79): a half-stop neutral
/// wedge around mid-gray followed by chromatic patches, two of them outside sRGB.
public enum RAWDevelopChart {
    /// Linear Display P3 → linear sRGB (both D65).
    static let linearSRGBFromP3 =
        SyntheticDNG.xyzFromLinearSRGB.inverse
        * simd_double3x3(rows: [
            SIMD3(0.4865709, 0.2656677, 0.1982173),
            SIMD3(0.2289746, 0.6917385, 0.0792869),
            SIMD3(0.0000000, 0.0451134, 1.0439444),
        ])

    public static let midGray = 0.18
    /// With the default camera the top three patches clip green at the sensor, and +3.5 also clips blue.
    public static let wedgeStops = Array(stride(from: -4.0, through: 3.5, by: 0.5))
    /// Display P3 colours with a negative linear sRGB component: P3 red at 0.9 (G −0.038,
    /// B −0.018 in sRGB) and a saturated green (R −0.118).
    public static let outOfSRGBP3: [SIMD3<Double>] = [[0.9, 0, 0], [0.05, 0.8, 0.1]]
    /// Linear sRGB: the six chromatic `SceneFixtures.patchesP3`, then `outOfSRGBP3`.
    public static let chromaticScene: [SIMD3<Double>] =
        SceneFixtures.patchesP3.prefix(6).map { linearSRGBFromP3 * SIMD3<Double>($0) }
        + outOfSRGBP3.map { linearSRGBFromP3 * $0 }
    static let neutralScene = wedgeStops.map { SIMD3(repeating: midGray * pow(2, $0)) }
    /// Linear sRGB scene: the neutral wedge, then the chromatic patches.
    public static let scene = neutralScene + chromaticScene
    public static let neutralIndices = neutralScene.indices
    public static let chromaticIndices = neutralScene.count..<scene.count
    public static let outOfSRGBIndices = (scene.count - outOfSRGBP3.count)..<scene.count
    /// Display P3 colours outside sRGB survive this camera's sensor.
    public static let camera = SyntheticDNG.wideGamutCameraFromXYZ

    public static func chart(cell: Int = 48) -> PatchChart { PatchChart(scene, cell: cell) }

    public static func cameraValues(_ scene: [SIMD3<Double>], cameraFromXYZ: simd_double3x3 = camera) -> [SIMD3<Double>] {
        scene.map { SyntheticDNG.camera(linearSRGB: $0, cameraFromXYZ: cameraFromXYZ) }
    }

    /// A DNG of `chart` (scene values in linear sRGB) as `camera` records it under D65.
    public static func dng(_ mosaic: SyntheticDNG.Mosaic, chart: PatchChart, baselineStops: Double = 0) -> Data {
        let sensor = PatchChart(cameraValues(chart.patches), cell: chart.cell, columns: chart.columns)
        return SyntheticDNG(
            mosaic: mosaic, width: chart.width, height: chart.height, baselineExposureStops: baselineStops,
            asShotNeutral: SyntheticDNG.daylightNeutral, cameraFromXYZ: camera
        ).data { sensor.value(x: $0, y: $1) }
    }
}
