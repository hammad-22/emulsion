# The digicam process

The digicam process (MOV-149) renders a mid-2000s compact CCD camera's in-camera JPEG, not a film
process. Code: `Renderer+Digicam.swift` (the graph), `DigicamModel.swift` (the Swift mirror of
`Kernels/Digicam.ci.metal`) and `DigicamLook.swift` (the constants below).

Scene light is cropped to the sensor's 4:3 frame and capped at its size, then passes a cheap lens
(vignette, soft corners, purple fringing), the camera's partial auto white balance, a noisy sensor
that clips hard per channel, saturation and a JPEG tone curve, then the in-camera sharpening and, for
an export, a real JPEG encode. Previews skip the encoder: at their size the 8 × 8 blocks would be
sub-pixel.

## Digicam constants

Status:
- **measured**: on period files or published lab tests (MOV-149);
- **owner direction**: an artistic choice from the MOV-149 review, which asked for a stronger, more
  washed-out look than the measurements, and so departs from some of them (said where it does);
- **artistic**: a choice with no measurement behind it.

Spatial sizes are in sensor pixels of a `sensorLongEdge` output, so a preview is close to a
downscale of the export.

| Constant | Value | Unit | Status | Source or reason |
| --- | --- | --- | --- | --- |
| `defaultNoise` | 0.75 | Grain amount | owner direction | Renders exactly as 0.6 did before the Noise control was rescaled (see `shotNoise`). |
| `defaultProcessing` | 0.7 | Halation amount | owner direction | Default in-camera processing. |
| `maximumNoise` | 1.0 | Grain amount | owner direction (14 Nov 2026) | Top of the Noise control; film grain reaches 2 (`FilmLook.maximumGrainAmount`). Reset returns Noise and Processing to these defaults (`Adjustments.defaults(for:)`). |
| `aspectRatio` | 4 / 3 | long ÷ short | measured | The compact-camera sensor format. |
| `sensorLongEdge` | 2592 | px | measured | 2592 × 1944 = 5.0 MP, from period file headers. |
| `vignetteStops` | 1.0 | stops at the corners, at processing 1 | owner direction | Radial falloff ∝ r²; unmeasured. |
| `lensSoftnessSigma` | 0.8 | sensor px | owner direction | A cheap lens is soft everywhere: the whole frame is blurred by this, whatever the processing amount. Owner direction and independent review; unmeasured. |
| `cornerSoftnessSigma` | 3.0 | sensor px × processing | owner direction | Towards the corners (weight ∝ r², full at the corner) the frame is blended into a blur of this × the processing amount, never less than the lens blur, so the corners are never sharper than the centre. Unmeasured. |
| `minimumBlurSigma` | 0.5 | output px | artistic | Below this a blur changes nothing visible, so it is skipped. |
| `fringeOnset` | 0.85 | fraction of the clip | owner direction | Purple fringing starts at this fraction of the clip, to keep it to near-clipped light: at 0.45 every bright grass blade turned violet. Unmeasured. |
| `fringeRadius` | 3.5 | sensor px | owner direction | Spread (sigma) of the fringe mask. Unmeasured. |
| `fringeColor` | (0.55, 0.2, 1.0) | linear sRGB | owner direction | Colour added by the fringe. Unmeasured. |
| `fringeStrength` | 1.0 | × processing, relative to the clip | owner direction | Strength of the fringe. Unmeasured. |
| `whiteBalanceCorrection` | 0.6 | fraction of the mired distance | owner direction | The simulated auto white balance corrects this fraction of the distance (mireds) from `whiteBalanceReference` to the as-shot light, so tungsten stays warm and shade cool. Earlier fitted to period compacts under tungsten (published lab tests: mid-gray R +9.5…11.6 %, B −9.9…−17 % in code values against a neutral render); the owner asked for a stronger cast beyond that range: at 2850 K it gives R +17.0 %, B −30.5 % (`DigicamTests`). |
| `whiteBalanceReference` | 5500 | K | artistic | Daylight, where the auto white balance starts. |
| `biasMireds` | 12 | mireds | owner direction | A constant cool cast added to the camera's white (positive renders cooler). |
| `biasMagenta` | 0.008 | fraction of the green gain | owner direction | A constant magenta cast, kept small so daylight skies read cool cyan-blue rather than lavender. |
| `warmthMireds` | 60 | mireds per unit of Warmth | artistic | White-balance shift of the Warmth control. |
| `tintGreen` | 0.12 | green gain per unit of Tint | artistic | Green-gain change of the Tint control. |
| `clipStops` | 2.0 | stops above mid-gray | owner direction | Highlights clip hard, per channel. Below ISO 12232's ≈ 2.5 stops and the +2.7…2.8 stops measured on period DSLR JPEGs. |
| `clip` | 0.18 × 2^`clipStops` | scene light | derived | Scene light that clips, before the white-balance gains. |
| `blackStops` | 4.5 | stops below mid-gray | artistic | Scene light this far below mid-gray reaches the black floor. Period DSLR JPEGs measured 4.6…4.7 stops. |
| `blackOffset` | 2^−(`clipStops` + `blackStops`) | fraction of the clip | derived | The offset removed before the tone curve. |
| `shotNoise` | 0.02 | σ at amount 1, fraction of the clip | owner direction | Shot noise ∝ √(signal / clip). At the default a flat patch two stops under mid-gray has a luma σ of 5.0 codes as exported (`DigicamTests`), beyond the ≈ 2 codes of our rough reading of period JPEGs (n = 4). The second review found Noise 1 too noisy, so amount 1 is 0.8 × the earlier 0.025: the slider's top end sits between the old default and the old maximum, which it can no longer reach. |
| `readNoise` | 0.006 | σ at amount 1, fraction of the clip | owner direction | A read-noise floor that dominates the shadows; 0.8 × the earlier 0.0075 (see `shotNoise`). |
| `chromaNoiseShare` | 2.0 | × the luminance noise | owner direction | Blotchy per-channel noise; being independent per channel, it adds luma noise as well as colour. |
| `chromaNoiseCell` | 6 | sensor px | owner direction | Cell size of the chroma noise. |
| `blueNoiseGain` | 1.25 | × the other channels | measured | Period files measured σ R/G/B ≈ 2.2/2.1/2.4. |
| `saturation` | 1.15 | linear-light, luma-preserving | measured | Period compacts render 109…117 % of the chart's saturation (published lab tests). Their extra red saturation and cyan turned toward blue are not modelled. |
| `colorBoost`, `colorCut` | 0.5, 0.8 | saturation per unit of Color, above / below 0 | artistic | Range of the Color control. |
| `middleGrayCode` | 118 / 255 | sRGB code | sourced | Scene mid-gray lands on 118: ISO 12232 standard output sensitivity. |
| `blackFloorCode` | 22 / 255 | sRGB code | owner direction | A lifted, greyish black floor. |
| `contrast` | 0.15 | share of the S curve | owner direction | The S curve is a square on each side of mid-gray; at the clip its slope is 1 − contrast, so highlights reach white without a shoulder. Flat midtones. |
| `toneCurvePivot` | derived | sRGB code | derived | The code that the black floor lift turns into `middleGrayCode`. |
| `gammaPower` | derived | power | derived | Power on the sRGB-encoded value that puts mid-gray on `toneCurvePivot`. |
| `sharpenRadius` | 1.8 | sensor px | owner direction | Unsharp mask on encoded luma: a wide sigma, for thick halos. |
| `sharpenAmount` | 1.85 | at processing 1 | owner direction | Set so a step edge at sensor size overshoots about 30 % of the step (measured 30.3 %; 20.7 % at the default; `DigicamTests`), informed by period compacts' published oversharpening figures (−3…22 %; those are MTF-based, not a step-edge overshoot). |
| `jpegQualityClean`, `jpegQualityLoss` | 0.9, 0.4 | Core Image JPEG quality | owner direction | Export quality is `jpegQualityClean − jpegQualityLoss × processing` (0.62 at the default, 0.5 at processing 1): more visible than period files, which measure IJG quality 93–98 with 4:2:2 chroma (Core Image at 0.85 is about IJG 95, with 4:2:0 chroma; its subsampling is not controlled here). |

## The model

- **White balance** (`DigicamModel.whiteBalanceGains`): von Kries channel gains (linear sRGB,
  luminance 1) for what the simulated camera leaves of the light. The develop has already
  neutralised the light, so the gains are the light ÷ the camera's white, where the camera's white is
  `whiteBalanceReference` moved `whiteBalanceCorrection` of the way (in mireds) towards the as-shot
  light, plus the constant cool-magenta bias and the user's Warmth and Tint.
- **Tone curve** (`DigicamModel.toneCurve`): light ÷ clip (0…1) → sRGB encode, the mid-gray power,
  the S curve blended in by `contrast`, then the lifted black floor.
- **Fringe**: the channel with the largest gain clips first, so the fringe mask starts at
  `clip ÷ max(gains)`.
- **Sensor frame**: the source is centre-cropped to 4:3 (landscape or portrait, as the source), moved
  to the origin and Lanczos-downscaled when its long edge exceeds the sensor's; it is clamped first so
  the edge pixels don't blend with transparency.
- **Export**: display light through a real JPEG encode and decode (sRGB, Core Image's encoder): the
  period cameras wrote sRGB JPEGs.
