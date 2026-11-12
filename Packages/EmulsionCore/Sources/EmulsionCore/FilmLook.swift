import Foundation
import simd

/// The stock Emulsion prints with, plus the texture and control constants the renderer uses.
/// The color and tone system itself is `FilmModel`.
public enum FilmLook {
    public static let stock = FilmModel()
    /// Width of the assumed frame: the full-aperture 35 mm camera gate, 0.980 in. The image's long
    /// edge maps to it (halation's spread, grain's pixel size). Other gauges are MOV-31.
    static let frameWidthMillimetres = 24.89
    /// Pixel side on the film in µm: the image's long edge spans the assumed frame width.
    static func micrometresPerPixel(longEdge: Double) -> Double { frameWidthMillimetres * 1000 / longEdge }
    /// Printer points per unit of the Warmth/Tint controls (log10 print exposure).
    public static let printerPoint = 0.05
    /// Saturation gain per unit of the Color control, above and below zero.
    public static let colorBoost = 0.5, colorCut = 0.8

    /// Display-referred sources (JPEG/HEIC): display white is estimated as a scene this many
    /// stops over mid-gray, and display black this many below. Engineering choices, not
    /// measurements: the film prints neither pure white nor pure black, so a finite estimate
    /// is picked that keeps edits smooth (see `FilmModel.SoftEnds`).
    static let displayCeilingStops = 4.0
    static let displayFloorStops = -9.0
    /// The scene-estimate bisection searches this far beyond the floor and ceiling.
    static let displaySearchMarginStops = 0.5
    /// Display-linear values between these knees pass to the neutral-response inversion
    /// unchanged; above and below, the soft ends bend them into the print's reachable range.
    /// Engineering choices, not measurements.
    static let displayShoulderKnee = 0.75
    static let displayToeKnee = 0.006
}
