import Foundation

/// The complete, deliberately small edit model, persisted per photo in the library index.
///
/// The controls are shared by both processes. In the digicam process exposure is set before the
/// sensor clip, Warmth and Tint shift the camera's white balance (channel gains, not printer
/// lights), Color is saturation, Grain is sensor noise and Halation is the in-camera processing
/// (purple fringing, corner softness, vignette, sharpening halos and, in exports, JPEG
/// compression; 0 is clean).
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
    /// Grain amount (see `grainRange(for:)`; 1 is the datasheet granularity) and halation (0 … 1).
    public var grain: Double = FilmLook.grainAmount
    public var halation: Double = 0.35
    /// Grain clump size (1…3, a frame that many times narrower) and its color part (0 mono … 1 measured).
    public var grainSize: Double = FilmLook.grainSize
    public var grainColor: Double = FilmLook.grainColor
    /// What stops halation at the back of the negative.
    public var backing: AntihalationBacking = .remJet
    public var process: RenderProcess = .film
    /// Grain pattern seed, fixed per photo so re-renders and exports match.
    public var seed: Double = 0
    /// RAW white balance, applied when the photo is developed (nil: as shot); the printer lights
    /// above act at print.
    public var whiteBalance: CameraWhiteBalance?

    public init() {}

    /// The Grain control's range: film grain to `FilmLook.maximumGrainAmount`, the digicam process's noise to 1.
    public static func grainRange(for process: RenderProcess) -> ClosedRange<Double> {
        switch process {
        case .film: 0...FilmLook.maximumGrainAmount
        case .digicam: 0...1
        }
    }
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
        a.grain = min(Self.grainRange(for: process).upperBound, max(0, grain))
        a.halation = min(1, max(0, halation))
        a.grainSize = min(3, max(1, grainSize))
        a.grainColor = min(1, max(0, grainColor))
        a.whiteBalance = whiteBalance?.clamped()
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
        func decode<Value: Decodable>(_ key: CodingKeys, into value: inout Value) throws {
            value = try saved.decodeIfPresent(Value.self, forKey: key) ?? value
        }
        try decode(.exposure, into: &exposure)
        try decode(.warmth, into: &warmth)
        try decode(.tint, into: &tint)
        try decode(.color, into: &color)
        try decode(.highlights, into: &highlights)
        try decode(.shadows, into: &shadows)
        try decode(.grain, into: &grain)
        try decode(.halation, into: &halation)
        try decode(.grainSize, into: &grainSize)
        try decode(.grainColor, into: &grainColor)
        try decode(.backing, into: &backing)
        try decode(.seed, into: &seed)
        try decode(.whiteBalance, into: &whiteBalance)
        // A process this version doesn't know (saved by a newer app) renders as film rather than
        // making the whole library index unreadable.
        process = (try? saved.decodeIfPresent(RenderProcess.self, forKey: .process)) ?? .film
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
