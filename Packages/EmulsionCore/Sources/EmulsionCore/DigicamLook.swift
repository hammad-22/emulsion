import Foundation

/// Constants of the digicam process (`Renderer+Digicam.swift`): a mid-2000s compact CCD camera's
/// in-camera JPEG. Each says whether it is measured (on period files or published lab tests, MOV-149)
/// or artistic; spatial sizes are in sensor pixels of a `sensorLongEdge` output.
public enum DigicamLook {
    /// Default amounts of the Grain (sensor noise) and Halation (in-camera processing) controls.
    /// Artistic.
    public static let defaultNoise = 0.35
    public static let defaultProcessing = 0.6

    // MARK: Geometry

    /// Sensor aspect ratio, long side over short (4:3, the compact-camera format).
    static let aspectRatio = 4.0 / 3.0
    /// Long edge of the sensor, pixels: 2592 × 1944 = 5.0 MP. Measured: period file headers.
    static let sensorLongEdge = 2592.0

    // MARK: Lens

    /// Light falloff at the corners, stops (radial, ∝ r²). Artistic, unmeasured.
    static let vignetteStops = 0.6
    /// Blur blended in towards the corners (weight ∝ r², full at the corner), sigma in sensor px. Artistic, unmeasured.
    static let cornerSoftnessSigma = 1.5
    /// Purple fringing around near-clip highlights: the mask starts at this fraction of the clip,
    /// spreads by this sigma (sensor px), and is added in this colour (linear sRGB) at this
    /// strength × the processing amount, relative to the clip level. Artistic, unmeasured.
    static let fringeOnset = 0.7
    static let fringeRadius = 2.5
    static let fringeColor = SIMD3(0.55, 0.2, 1.0)
    static let fringeStrength = 0.6

    // MARK: White balance

    /// The simulated auto white balance corrects this fraction of the distance (in mireds) from
    /// `whiteBalanceReference` to the light the photo was shot under, so tungsten stays warm and
    /// shade slightly cool. Fitted to period compacts under tungsten (measured, published lab tests:
    /// mid-gray R +9.5…11.6 %, B −9.9…−17 % in code values against a neutral render). A residual
    /// along the Planckian locus can't hold both: at 2850 K this gives R +9.6 %, B −19.5 % (`DigicamTests`).
    static let whiteBalanceCorrection = 0.8
    /// Kelvin the auto white balance starts from (daylight). Artistic.
    static let whiteBalanceReference = 5500.0
    /// A constant cool cast, mireds added to the camera's white (positive renders cooler). Artistic.
    static let biasMireds = 4.0
    /// A constant magenta cast: green gain lowered by this fraction. Artistic.
    static let biasMagenta = 0.015
    /// Mireds of white-balance shift per unit of Warmth, and green-gain change per unit of Tint. Artistic.
    static let warmthMireds = 60.0
    static let tintGreen = 0.12

    // MARK: Sensor

    /// Highlights clip hard, per channel, this many stops above mid-gray (scene 0.18). Artistic,
    /// consistent with ISO 12232 standard output sensitivity (mid-gray at code 118 with an sRGB
    /// curve leaves about 2.5 stops); period DSLR JPEGs measured +2.7…2.8 stops.
    static let clipStops = 2.5
    /// Scene light this many stops below mid-gray renders black: the offset removed before the
    /// tone curve. Artistic; period DSLR JPEGs measured 4.6…4.7 stops.
    static let blackStops = 4.5
    /// `blackStops` as a fraction of the clip level.
    static let blackOffset = pow(2, -(clipStops + blackStops))
    /// Noise σ at amount 1, as a fraction of the clip level: shot noise ∝ √(signal / clip), plus a
    /// read-noise floor. Blotchy chroma noise is `chromaNoiseShare` of the luminance noise, in
    /// cells of `chromaNoiseCell` sensor px. Set so a flat patch two stops under mid-gray has a
    /// luma σ of about 2 sRGB codes at the default amount (`DigicamTests`). Measured: our rough
    /// reading of period JPEGs (n = 4).
    static let shotNoise = 0.024
    static let readNoise = 0.0048
    static let chromaNoiseShare = 1.5
    static let chromaNoiseCell = 4.0

    // MARK: Colour and tone

    /// Saturation in linear light at Color 0 (luma-preserving). Measured: period compacts render
    /// 109…117 % of the chart's saturation (published lab tests). Their extra red saturation and
    /// cyan turned toward blue are not modelled.
    static let saturation = 1.15
    /// Saturation change per unit of the Color control, above and below zero. Artistic.
    static let colorBoost = 0.5, colorCut = 0.8
    /// sRGB code that scene mid-gray lands on (118 of 255): ISO 12232 standard output sensitivity.
    static let middleGrayCode = 118.0 / 255.0
    /// S contrast curve around mid-gray: its power and the share of it blended in. At the clip the
    /// curve's slope is 1 − contrast, so highlights reach white without a shoulder. Artistic.
    static let contrastPower = 2.0
    static let contrast = 0.5

    // MARK: Processing

    /// Unsharp mask on encoded luma: sigma in sensor px, and the amount at processing 1, set so a
    /// step edge at sensor size overshoots about 18 % of the step (`DigicamTests`). Measured: period
    /// compacts oversharpen 9…21 % (published lab tests).
    static let sharpenRadius = 1.2
    static let sharpenAmount = 0.55
    /// Core Image JPEG quality whenever processing is on; only renders at sensor size are
    /// compressed. Period files measure about IJG quality 93; Apple's scale isn't IJG's, so this is
    /// an artistic approximation. Period files used 4:2:2 chroma; Core Image chooses its own
    /// subsampling, which is not controlled here.
    static let jpegQuality = 0.85
}
