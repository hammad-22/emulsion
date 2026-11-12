import CoreGraphics
import CoreImage
import Foundation
import simd

/// Scene-light fixtures: linear sRGB working values (unless a fixture says otherwise), 0.18 is
/// mid-gray. Patch rows are one pixel per patch.
public enum SceneFixtures {
    public static let linear = Fixtures.linearSRGB
    public static let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    /// Scene mid-gray (18%). Kept in Double so the wedge rounds each step to Float only once.
    static let midGrayDouble = 0.18
    static let midGray = Float(midGrayDouble)

    /// Neutral exposure wedge from −8 to +6 stops around mid-gray.
    public static func wedge(steps: Int = 141) -> (image: CIImage, stops: [Double]) {
        let stops = (0..<steps).map { -8 + 14 * Double($0) / Double(steps - 1) }
        let image = Fixtures.image(width: steps, height: 1, space: linear) { x, _ in
            SIMD3(repeating: Float(midGrayDouble * pow(2, stops[x])))
        }
        return (image, stops)
    }
    /// Flat scene patch of one value, any size (grain statistics, preview/export).
    public static func flat(_ value: Float, width: Int = 256, height: Int = 256) -> CIImage {
        Fixtures.image(width: width, height: height, space: linear) { _, _ in SIMD3(repeating: value) }
    }
    /// A small, very bright source on a dark scene (halation).
    public static func highlightPoint(size: Int = 400, radius: Float = 6, level: Float = 40) -> CIImage {
        Fixtures.image(width: size, height: size, space: linear) { x, y in
            hypot(Float(x - size / 2), Float(y - size / 2)) < radius * Float(size) / 400 ? SIMD3(repeating: level) : SIMD3(repeating: 0.02)
        }
    }
    /// A disc of `light` (linear Display P3) on a neutral background, centred in a square frame.
    public static func disc(size: Int, radius: Float, light: SIMD3<Float>, background: Float = 0.02) -> CIImage {
        Fixtures.image(width: size, height: size, space: linearP3) { x, y in
            hypot(Float(x - size / 2), Float(y - size / 2)) < radius ? light : SIMD3(repeating: background)
        }
    }
    /// A hard vertical edge: the left half `bright`, the right half `dark` (neutral scene light).
    public static func edge(width: Int = 800, height: Int = 400, bright: Float = 16, dark: Float = 0.02) -> CIImage {
        Fixtures.image(width: width, height: height, space: linear) { x, _ in SIMD3(repeating: x < width / 2 ? bright : dark) }
    }
    /// Colored scene patches (linear Display P3 → working space), incl. saturated neon.
    public static let patchesP3: [SIMD3<Float>] = [
        [0.40, 0.20, 0.13], [0.12, 0.20, 0.45], [0.10, 0.25, 0.06],
        [0.55, 0.04, 0.03], [0.02, 0.35, 0.60], [0.60, 0.05, 0.50], [0.18, 0.18, 0.18],
    ]
    public static func patches(cell: Int = 64) -> CIImage {
        Fixtures.image(width: cell * patchesP3.count, height: cell, space: linearP3) {
            x, _ in
            patchesP3[x / cell]
        }
    }

    // MARK: Visual regression scenes (MOV-37)

    /// A 24-patch colour chart as scene reflectances in the working space, in patch order. Values
    /// copied from `chart24` in `References/delta-e.json` (written by
    /// `Tools/color-references/generate_delta_e_references.py`), rounded to 6 significant digits;
    /// `chartFixtureMatchesColourScience` checks them.
    public static let chart24Patches: [(name: String, linear: SIMD3<Float>)] = [
        ("dark skin", [0.173023, 0.0821106, 0.0567506]),
        ("light skin", [0.568405, 0.292652, 0.218356]),
        ("blue sky", [0.103498, 0.195953, 0.33152]),
        ("foliage", [0.101541, 0.148918, 0.0519452]),
        ("blue flower", [0.221586, 0.215861, 0.434716]),
        ("bluish green", [0.107993, 0.514357, 0.412929]),
        ("orange", [0.747304, 0.200626, 0.0281596]),
        ("purplish blue", [0.057528, 0.105126, 0.403156]),
        ("moderate red", [0.566886, 0.0842787, 0.119729]),
        ("purple", [0.111078, 0.0422893, 0.143036]),
        ("yellow green", [0.345612, 0.508728, 0.0494407]),
        ("orange yellow", [0.794684, 0.359391, 0.020561]),
        ("blue", [0.0170599, 0.0502029, 0.292256]),
        ("green", [0.0560232, 0.300135, 0.0687601]),
        ("red", [0.456038, 0.0303543, 0.0408739]),
        ("yellow", [0.857378, 0.567627, 0.00680114]),
        ("magenta", [0.533705, 0.0885932, 0.307636]),
        ("cyan", [-0.0375258, 0.246997, 0.400517]),
        ("white 9.5 (.05 D)", [0.911912, 0.915085, 0.89398]),
        ("neutral 8 (.23 D)", [0.579733, 0.592033, 0.593736]),
        ("neutral 6.5 (.44 D)", [0.354944, 0.365377, 0.367758]),
        ("neutral 5 (.70 D)", [0.190087, 0.191796, 0.193187]),
        ("neutral 3.5 (1.05 D)", [0.085224, 0.0888901, 0.0926113]),
        ("black 2 (1.5 D)", [0.0303783, 0.0311786, 0.0328194]),
    ]

    public static func chart24() -> CIImage { Fixtures.row(chart24Patches.map(\.linear), space: linear) }

    /// The six Display P3 primaries and secondaries (R, G, B, C, M, Y) in linear P3, each channel at
    /// 0.18·2^stops, for every stop in turn: +4 stops reaches 2.88, saturated highlights above 1.0.
    public static func primaries(stops: [Float] = [-2, 0, 2, 4]) -> CIImage {
        let hues: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 1, 1], [1, 0, 1], [1, 1, 0]]
        return Fixtures.row(stops.flatMap { stop in hues.map { $0 * midGray * pow(2, stop) } }, space: linearP3)
    }

    /// Skin-like: the chart's two skin patches across exposure; not a measured skin-tone set.
    public static func skinLike() -> CIImage {
        let skins = chart24Patches.prefix(2).map(\.linear)
        let stops: [Float] = [-1.5, -0.5, 0.5, 1.5]
        return Fixtures.row(skins.flatMap { skin in stops.map { skin * pow(2, $0) } }, space: linear)
    }

    /// Spatial scene for local tone, halation and grain: a horizontal exposure ramp from −5 to +4
    /// stops around mid-gray; top third neutral, middle third warm, bottom third cool; a hard-edged
    /// bright square in the dark quarter and a dark square in the bright quarter.
    public static func gradientScene(width: Int = 240, height: Int = 160) -> CIImage {
        let (lowStops, spanStops): (Float, Float) = (-5, 9)
        let tints: [SIMD3<Float>] = [[1, 1, 1], [1.25, 1, 0.75], [0.75, 1, 1.25]]
        let square = 12
        let (brightLevel, darkLevel): (Float, Float) = (8, 0.01)
        func inSquare(_ x: Int, _ row: Int, centerX: Int) -> Bool {
            (centerX - square / 2..<centerX + square / 2).contains(x) && (height / 2 - square / 2..<height / 2 + square / 2).contains(row)
        }
        return Fixtures.image(width: width, height: height, space: linear) { x, y in
            let row = height - 1 - y
            if inSquare(x, row, centerX: width / 8) { return SIMD3(repeating: brightLevel) }
            if inSquare(x, row, centerX: width * 7 / 8) { return SIMD3(repeating: darkLevel) }
            let stops = lowStops + spanStops * Float(x) / Float(width - 1)
            return midGray * pow(2, stops) * tints[min(2, row * 3 / height)]
        }
    }
}
