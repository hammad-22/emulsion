import Foundation

/// Constants of the digicam process (`Renderer+Digicam.swift`): a mid-2000s compact CCD camera's
/// in-camera JPEG. Each says whether it is measured (on period files or published lab tests, MOV-149),
/// artistic, or an artistic owner direction from the MOV-149 review, which asked for a stronger,
/// more washed-out look than the measurements and so departs from some of them (said where it does).
/// Spatial sizes are in sensor pixels of a `sensorLongEdge` output.
enum DigicamLook {
    /// Default amounts of the Grain (sensor noise) and Halation (in-camera processing) controls.
    /// Artistic, owner direction (MOV-149 review).
    static let defaultNoise = 0.6
    static let defaultProcessing = 0.7

    // MARK: Geometry

    /// Sensor aspect ratio, long side over short (4:3, the compact-camera format).
    static let aspectRatio = 4.0 / 3.0
    /// Long edge of the sensor, pixels: 2592 × 1944 = 5.0 MP. Measured: period file headers.
    static let sensorLongEdge = 2592.0

    // MARK: Lens

    /// Light falloff at the corners, stops (radial, ∝ r²), at processing 1. Artistic, owner
    /// direction (MOV-149 review); unmeasured.
    static let vignetteStops = 1.0
    /// A cheap lens is soft everywhere: the whole frame is blurred by `lensSoftnessSigma` (whatever
    /// the processing amount) and, towards the corners (weight ∝ r², full at the corner), blended
    /// into a blur of `cornerSoftnessSigma` × the processing amount; sigmas in sensor px, each skipped
    /// below `minimumBlurSigma`. Artistic, owner direction and independent review (MOV-149); unmeasured.
    static let lensSoftnessSigma = 0.8
    static let cornerSoftnessSigma = 3.0
    /// Below this sigma (output px) a blur changes nothing visible, so it is skipped.
    static let minimumBlurSigma = 0.5
    /// Purple fringing around near-clip highlights: the mask starts at this fraction of the clip,
    /// spreads by this sigma (sensor px), and is added in this colour (linear sRGB) at this
    /// strength × the processing amount, relative to the clip level. The onset keeps it to near-clipped
    /// light: at 0.45 every bright grass blade turned violet. Artistic, owner direction (MOV-149 review); unmeasured.
    static let fringeOnset = 0.85
    static let fringeRadius = 3.5
    static let fringeColor = SIMD3(0.55, 0.2, 1.0)
    static let fringeStrength = 1.0

    // MARK: White balance

    /// The simulated auto white balance corrects this fraction of the distance (in mireds) from
    /// `whiteBalanceReference` to the light the photo was shot under, so tungsten stays warm and
    /// shade cool. Earlier fitted to the red shift of period compacts under tungsten (published lab
    /// tests: mid-gray R +9.5…11.6 %, B −9.9…−17 % in code values against a neutral render); now
    /// artistic, owner direction (MOV-149 review), a stronger cast beyond that range: at 2850 K this
    /// gives R +17.0 %, B −30.5 % (`DigicamTests`).
    static let whiteBalanceCorrection = 0.6
    /// Kelvin the auto white balance starts from (daylight). Artistic.
    static let whiteBalanceReference = 5500.0
    /// A constant cool cast, mireds added to the camera's white (positive renders cooler). Artistic,
    /// owner direction (MOV-149 review).
    static let biasMireds = 12.0
    /// A constant magenta cast: green gain lowered by this fraction. Artistic, kept small so daylight
    /// skies read cool cyan-blue rather than lavender (MOV-149 review).
    static let biasMagenta = 0.008
    /// Mireds of white-balance shift per unit of Warmth, and green-gain change per unit of Tint. Artistic.
    static let warmthMireds = 60.0
    static let tintGreen = 0.12

    // MARK: Sensor

    /// Highlights clip hard, per channel, this many stops above mid-gray (scene 0.18). Artistic,
    /// owner direction (MOV-149 review): below ISO 12232's ≈ 2.5 stops and the +2.7…2.8 stops
    /// measured on period DSLR JPEGs.
    static let clipStops = 2.0
    /// Scene light that clips, before the white-balance gains.
    static let clip = 0.18 * pow(2, clipStops)
    /// Scene light this many stops below mid-gray reaches the black floor: the offset removed before
    /// the tone curve. Artistic; period DSLR JPEGs measured 4.6…4.7 stops.
    static let blackStops = 4.5
    /// `blackStops` as a fraction of the clip level.
    static let blackOffset = pow(2, -(clipStops + blackStops))
    /// Noise σ at amount 1, as a fraction of the clip level: shot noise ∝ √(signal / clip), plus a
    /// read-noise floor that dominates the shadows. Blotchy per-channel noise is `chromaNoiseShare` of
    /// the luminance noise, in cells of `chromaNoiseCell` sensor px; being independent per channel,
    /// it adds luma noise as well as colour. The blue channel's noise is `blueNoiseGain` × the others
    /// (period files measured σ R/G/B ≈ 2.2/2.1/2.4). Artistic, owner direction (MOV-149 review): at
    /// the default a flat patch two stops under mid-gray has a luma σ of 5.0 codes as exported
    /// (`DigicamTests`), beyond the ≈ 2 codes of our rough reading of period JPEGs (n = 4).
    static let shotNoise = 0.025
    static let readNoise = 0.0075
    static let chromaNoiseShare = 2.0
    static let chromaNoiseCell = 6.0
    static let blueNoiseGain = 1.25

    // MARK: Colour and tone

    /// Saturation in linear light at Color 0 (luma-preserving). Measured: period compacts render
    /// 109…117 % of the chart's saturation (published lab tests). Their extra red saturation and
    /// cyan turned toward blue are not modelled.
    static let saturation = 1.15
    /// Saturation change per unit of the Color control, above and below zero. Artistic.
    static let colorBoost = 0.5, colorCut = 0.8
    /// sRGB code that scene mid-gray lands on (118 of 255): ISO 12232 standard output sensitivity.
    static let middleGrayCode = 118.0 / 255.0
    /// sRGB code of black: a lifted, greyish floor. Artistic, owner direction (MOV-149 review).
    static let blackFloorCode = 22.0 / 255.0
    /// Share of the S contrast curve (a square on each side of mid-gray) blended in. At the clip its
    /// slope is 1 − contrast, so highlights reach white without a shoulder. Artistic, owner
    /// direction (MOV-149 review): flat midtones.
    static let contrast = 0.15
    /// Where the S curve pivots: the code that the black floor lift turns into `middleGrayCode`.
    static let toneCurvePivot = (middleGrayCode - blackFloorCode) / (1 - blackFloorCode)
    /// Power on the sRGB-encoded value that puts mid-gray on `toneCurvePivot`.
    static let gammaPower: Double = {
        let middleGray = (0.18 / clip - blackOffset) / (1 - blackOffset)
        return log(toneCurvePivot) / log(ColorMath.encodeSRGB(middleGray))
    }()

    // MARK: Processing

    /// Unsharp mask on encoded luma: sigma in sensor px (wide, for thick halos), and the amount at
    /// processing 1, set so a step edge at sensor size overshoots about 30 % of the step (measured
    /// 30.3 %; 20.7 % at the default; `DigicamTests`). Artistic, owner direction (MOV-149 review), informed by period compacts'
    /// published oversharpening figures (−3…22 %; those are MTF-based, not a step-edge overshoot).
    static let sharpenRadius = 1.8
    static let sharpenAmount = 1.85
    /// Core Image JPEG quality of an export: `jpegQualityClean − jpegQualityLoss × processing`
    /// (0.62 at the default, 0.5 at processing 1). Artistic, owner direction (MOV-149 review): more
    /// visible than period files, which measure IJG quality 93–98 with 4:2:2 chroma (Core Image at
    /// 0.85 is about IJG 95, with 4:2:0 chroma; its subsampling is not controlled here).
    static let jpegQualityClean = 0.9
    static let jpegQualityLoss = 0.4
}
