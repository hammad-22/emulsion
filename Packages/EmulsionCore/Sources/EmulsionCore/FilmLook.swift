import Foundation
import simd

/// The stock Emulsion prints with, plus the texture and control constants the renderer uses.
/// The color and tone system itself is `FilmModel`.
public enum FilmLook {
    public static let stock = FilmModel()
    /// Halation threshold in scene-linear luminance (~+3.5 stops over mid-gray).
    public static let halationThreshold = 2.0
    /// Halation: a tight core plus a soft skirt, radii as fractions of the long edge.
    public static let halationRadius = 0.004
    public static let halationSkirt = 0.016
    /// Share of halation energy in the tight core; the rest goes to the soft skirt.
    public static let halationCoreShare = 0.55
    /// Grain cell size as a fraction of the long edge (≈1.7 px at 4032).
    public static let grainCell = 1.0 / 2400
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
    /// Display-linear values between these knees are estimated exactly; above and below, the
    /// soft ends bend them into the print's reachable range. Engineering choices, not measurements.
    static let displayShoulderKnee = 0.75
    static let displayToeKnee = 0.006
}
