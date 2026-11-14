import Foundation

/// Constants of the digicam process (`Renderer+Digicam.swift`): a mid-2000s compact CCD camera's
/// in-camera JPEG. Each says whether it is measured (period files or published lab tests, MOV-149),
/// artistic, or an *owner direction*: an artistic choice from the MOV-149 review, which asked for a
/// stronger, more washed-out look than the measurements (said where it departs from them).
/// Spatial sizes are in sensor pixels of a `sensorLongEdge` output.
enum DigicamLook {
    /// Default Grain (sensor noise) and Halation (in-camera processing) amounts. Owner direction.
    /// The noise default renders exactly as 0.6 did before the Noise control was rescaled (`shotNoise`).
    static let defaultNoise = 0.75
    static let defaultProcessing = 0.7

    // MARK: Geometry

    /// Long side over short: 4:3, the compact-camera format.
    static let aspectRatio = 4.0 / 3.0
    /// 2592 × 1944 = 5.0 MP. Measured: period file headers.
    static let sensorLongEdge = 2592.0

    // MARK: Lens

    /// Corner light falloff at processing 1, stops, radial ∝ r². Owner direction; unmeasured.
    static let vignetteStops = 1.0
    /// A cheap lens is soft everywhere: the whole frame is blurred by `lensSoftnessSigma` and,
    /// towards the corners (weight ∝ r²), blended into a blur of `cornerSoftnessSigma` × processing,
    /// never less than the lens blur. Sensor px. Owner direction and independent review; unmeasured.
    static let lensSoftnessSigma = 0.8
    static let cornerSoftnessSigma = 3.0
    /// Below this sigma (output px) a blur changes nothing visible, so it is skipped.
    static let minimumBlurSigma = 0.5
    /// Purple fringing around near-clip highlights: the mask starts at `fringeOnset` × the clip,
    /// spreads by `fringeRadius` (sensor px) and adds `fringeColor` (linear sRGB) at `fringeStrength`
    /// × processing, relative to the clip. At an onset of 0.45 every bright grass blade turned
    /// violet. Owner direction; unmeasured.
    static let fringeOnset = 0.85
    static let fringeRadius = 3.5
    static let fringeColor = SIMD3(0.55, 0.2, 1.0)
    static let fringeStrength = 1.0

    // MARK: White balance

    /// The simulated auto white balance corrects this fraction of the distance (mireds) from
    /// `whiteBalanceReference` to the as-shot light, so tungsten stays warm and shade cool. Owner
    /// direction, beyond period compacts under tungsten (published lab tests: mid-gray R +9.5…11.6 %,
    /// B −9.9…−17 % against a neutral render); at 2850 K it gives R +17.0 %, B −30.5 % (`DigicamTests`).
    static let whiteBalanceCorrection = 0.6
    /// Daylight, where the auto white balance starts, kelvin. Artistic.
    static let whiteBalanceReference = 5500.0
    /// Constant cool cast, mireds added to the camera's white. Owner direction.
    static let biasMireds = 12.0
    /// Constant magenta cast: green gain lowered by this fraction, small so daylight skies read
    /// cyan-blue rather than lavender. Owner direction.
    static let biasMagenta = 0.008
    /// Mireds per unit of Warmth, and green-gain change per unit of Tint. Artistic.
    static let warmthMireds = 60.0
    static let tintGreen = 0.12

    // MARK: Sensor

    /// Highlights clip hard, per channel, this many stops above mid-gray. Owner direction: below
    /// ISO 12232's ≈ 2.5 stops and the +2.7…2.8 stops measured on period DSLR JPEGs.
    static let clipStops = 2.0
    /// Scene light that clips, before the white-balance gains.
    static let clip = 0.18 * pow(2, clipStops)
    /// Scene light this many stops below mid-gray reaches the black floor. Artistic; period DSLR
    /// JPEGs measured 4.6…4.7 stops.
    static let blackStops = 4.5
    /// `blackStops` as a fraction of the clip: the offset removed before the tone curve.
    static let blackOffset = pow(2, -(clipStops + blackStops))
    /// Noise σ at amount 1, as a fraction of the clip: shot noise ∝ √(signal / clip) plus a
    /// read-noise floor that dominates the shadows. Blotchy per-channel noise is `chromaNoiseShare`
    /// × the luminance noise, in `chromaNoiseCell` sensor-px cells, so it adds luma noise too. Blue
    /// is `blueNoiseGain` × the others (period files: σ R/G/B ≈ 2.2/2.1/2.4).
    /// Owner direction: at the default, a flat patch two stops under mid-gray has a luma σ of 5.0
    /// codes as exported (`DigicamTests`), beyond the ≈ 2 codes of period JPEGs (rough, n = 4).
    /// Amount 1 is 0.8 × the earlier 0.025 / 0.0075, which the second review found too noisy.
    static let shotNoise = 0.02
    static let readNoise = 0.006
    static let chromaNoiseShare = 2.0
    static let chromaNoiseCell = 6.0
    static let blueNoiseGain = 1.25

    // MARK: Colour and tone

    /// Luma-preserving saturation in linear light at Color 0. Measured: period compacts render
    /// 109…117 % of the chart's saturation (published lab tests). Their extra red saturation and
    /// cyan turned toward blue are not modelled.
    static let saturation = 1.15
    /// Saturation change per unit of Color, above and below zero. Artistic.
    static let colorBoost = 0.5, colorCut = 0.8
    /// Mid-gray lands on sRGB code 118 of 255: ISO 12232 standard output sensitivity.
    static let middleGrayCode = 118.0 / 255.0
    /// A lifted, greyish black. Owner direction.
    static let blackFloorCode = 22.0 / 255.0
    /// Share of the S curve (a square on each side of mid-gray) blended in; at the clip its slope is
    /// 1 − contrast, so highlights reach white without a shoulder. Owner direction: flat midtones.
    static let contrast = 0.15
    /// Where the S curve pivots: the code that the black floor lift turns into `middleGrayCode`.
    static let toneCurvePivot = (middleGrayCode - blackFloorCode) / (1 - blackFloorCode)
    /// Power on the sRGB-encoded value that puts mid-gray on `toneCurvePivot`.
    static let gammaPower: Double = {
        let middleGray = (0.18 / clip - blackOffset) / (1 - blackOffset)
        return log(toneCurvePivot) / log(ColorMath.encodeSRGB(middleGray))
    }()

    // MARK: Processing

    /// Unsharp mask on encoded luma: a wide sigma (sensor px) for thick halos, and the amount at
    /// processing 1, so a step edge at sensor size overshoots about 30 % (measured 30.3 %, 20.7 % at
    /// the default; `DigicamTests`). Owner direction, informed by period compacts' published
    /// oversharpening (−3…22 %, MTF-based rather than step-edge overshoot).
    static let sharpenRadius = 1.8
    static let sharpenAmount = 1.85
    /// Export JPEG quality: `jpegQualityClean − jpegQualityLoss × processing` (0.62 at the default,
    /// 0.5 at 1). Owner direction: more visible than period files, which measure IJG quality 93–98
    /// with 4:2:2 chroma (Core Image at 0.85 is about IJG 95, 4:2:0; subsampling isn't controlled).
    static let jpegQualityClean = 0.9
    static let jpegQualityLoss = 0.4
}
