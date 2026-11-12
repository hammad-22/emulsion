import Foundation
import simd

/// The stock Emulsion prints with, plus the texture and control constants the renderer uses.
/// The color and tone system itself is `FilmModel`; its parameters come from a stock file.
public enum FilmLook {
    /// The default stock, `Resources/Stocks/emulsion-default.json`.
    public static let stock: FilmModel = {
        do throws(EmulsionError) {
            return try FilmModel(stock: .bundled(named: "emulsion-default"))
        } catch {
            // The default ships inside the engine and is tested, so failing here is a build mistake, not user input.
            fatalError("The bundled default stock is unusable: \(error.developerDescription)")
        }
    }()
    /// Width of the assumed frame: the full-aperture 35 mm camera gate, 0.980 in. The image's long
    /// edge maps to it. Other gauges are MOV-31.
    static let frameWidthMillimetres = 24.89
    /// Film base thickness. Estimated: a typical triacetate camera-film base; the VISION3 sheets
    /// do not state it.
    static let baseThicknessMicrometres = 140.0
    /// Share of diffuse light entering a base of index 1.48 that its back surface returns to the
    /// emulsion (Fresnel plus total internal reflection), derived in `Tools/halation-kernel`
    /// (`geometry.returned_fraction`).
    static let halationReturnFraction = 0.584
    /// Green layer's share of the red layer's halation. Estimated: the green layer sits above the
    /// red one, so the returning light reaches it second.
    static let halationGreenShare = 0.25
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
    /// Display-linear values between these knees pass to the neutral-response inversion
    /// unchanged; above and below, the soft ends bend them into the print's reachable range.
    /// Engineering choices, not measurements.
    static let displayShoulderKnee = 0.75
    static let displayToeKnee = 0.006
}
