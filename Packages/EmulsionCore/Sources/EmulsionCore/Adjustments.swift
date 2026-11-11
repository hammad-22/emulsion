import Foundation

/// The complete, deliberately small edit model, persisted per photo in the library index.
public struct Adjustments: Codable, Equatable, Sendable {
    /// Scene exposure in stops (−3…3).
    public var exposure: Double = 0
    /// Printer-light warmth (−1 cool … 1 warm) and tint (−1 green … 1 magenta).
    public var warmth: Double = 0
    public var tint: Double = 0
    /// Color density (−1 … 1; 0 is the look).
    public var color: Double = 0
    /// Local tone (−1 … 1). Positive highlights recover, positive shadows lift.
    public var highlights: Double = 0
    public var shadows: Double = 0
    /// Texture (0 … 1).
    public var grain: Double = 0.35
    public var halation: Double = 0.35
    /// Grain pattern seed, fixed per photo so re-renders and exports match.
    public var seed: Double = 0

    public init() {}
    public static let neutral: Adjustments = {
        var a = Adjustments()
        a.grain = 0
        a.halation = 0
        return a
    }()

    public func clamped() -> Adjustments {
        var a = self
        a.exposure = min(3, max(-3, exposure))
        for k in [\Adjustments.warmth, \.tint, \.color, \.highlights, \.shadows] { a[keyPath: k] = min(1, max(-1, a[keyPath: k])) }
        a.grain = min(1, max(0, grain))
        a.halation = min(1, max(0, halation))
        return a
    }
}

extension Adjustments {
    /// Reads edits saved by any version. A field missing from the file keeps its default,
    /// so adding a field never makes an existing library unreadable (MOV-128). Every
    /// stored property needs a line here; `AdjustmentsCodingTests` checks the count.
    public init(from decoder: any Decoder) throws {
        self.init()
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        func decode(_ key: CodingKeys, into value: inout Double) throws {
            value = try saved.decodeIfPresent(Double.self, forKey: key) ?? value
        }
        try decode(.exposure, into: &exposure)
        try decode(.warmth, into: &warmth)
        try decode(.tint, into: &tint)
        try decode(.color, into: &color)
        try decode(.highlights, into: &highlights)
        try decode(.shadows, into: &shadows)
        try decode(.grain, into: &grain)
        try decode(.halation, into: &halation)
        try decode(.seed, into: &seed)
    }
}

extension Adjustments {
    /// User printer lights (log10 print exposure), added to the calibrated ones. Lab convention:
    /// more light in a channel prints more of its complementary dye, so Warmth adds blue light
    /// and removes red; Tint adds green.
    var printerLights: SIMD3<Double> { SIMD3(-warmth, tint, warmth) * FilmLook.printerPoint }
    /// Saturation the film system applies to the scene, from the Color control.
    var printSaturation: Double { 1 + color * (color >= 0 ? FilmLook.colorBoost : FilmLook.colorCut) }
}
