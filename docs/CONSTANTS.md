# Constants and their sources

The long form of the comments in `Packages/EmulsionCore` outside the film model: where each number
comes from, what the code assumes, and why. The code keeps a one-line comment and points here, by
section (the type's name). The film model's own physics is in `FILM-THEORY.md`, the engine's
pipeline in `ENGINE.md` and the digicam process in `DIGICAM.md`.

Status words: **sourced** (a standard, paper or datasheet), **measured** (on this engine, Apple's
decoder or real files), **artistic** (a choice).

# Inputs (EmulsionCore)

## InputColorSpace

Camera and display encodings Emulsion can read, each decoded to linear light (0.18 = mid-gray) in
the linear sRGB / D65 working space; `contract` says what that light means. Curves and primaries
follow each manufacturer's published white paper, cross-checked against the colour-science library
(`Tools/color-references/`).

- **Contracts.** Display-referred sources (Rec.709, Display P3) get a scene estimate and are printed
  relative to themselves; HLG is nominally scene-referred; everything else is decoded as scene light
  by its curve.
- **Code values or E′** (`formulaTakesCodeValues`). Sony (S-Log3 18 % = code 420), ARRI LogC3 (400)
  and Panasonic (V-Log 433) publish their formulas on 10-bit legal-range code values ÷ 1023; BT.2100
  HLG, Apple Log and ARRI LogC4 (whose spec plots E′ over the whole integer range) take the normalized
  signal E′.
- **Formula range** (`formulaRange`): the range in which a code value is its formula's own input:
  legal for code-value curves (S-Log3 gray = 420 / 1023), full for the rest (HLG gray = 0.38).
- **Signal → formula input** (`curveInputFromSignal`): code / 1023 = (64 + 876·E′) / 1023 for
  code-value curves (BT.2100 narrow range), E′ itself otherwise.
- **Default Y′CbCr matrix** for an untagged frame: BT.2100 specifies BT.2020 for HLG, and Apple Log
  is recorded in BT.2020; for the other inputs BT.709 is the common tag, an assumption rather than a
  camera specification.
- **Working space** (`toWorking`): source RGB → linear sRGB (D65), with Bradford adaptation for
  white points other than D65 (ACES AP1).
- **D65**: x 0.3127, y 0.3290, as the colour standards round it (sRGB, Rec. 709/2020, Display P3).

## TransferCurve

The raw value is the curve identifier the `inputTransform` kernel switches on (`decodeCurve` in
`Emulsion.ci.metal`), so it must match the Metal source. ARRI LogC3 is the EI 800 curve. BT.1886 is
the display gamma 2.4; sRGB is the IEC 61966-2-1 piecewise transfer.

## ColorMath

- **`decode`** is the Swift reference decode, mirroring `decodeCurve`, from each curve's own domain:
  code value / 1023 or signal E′ (see `InputColorSpace` above). S-Log3 is defined on 10-bit code
  value / 1023 as reflection.
- **HLG**: the BT.2100 inverse OETF (constants a, b, c from ITU-R BT.2100), scaled so 38 % signal is
  18 % gray (ITU-R BT.2408). Sub-black signals mirror (odd extension) so the curve stays monotonic.
- **BT.1886**: odd extension below 0, the sub-black policy (`ENGINE.md`).
- **LogC4**: the constants of the ARRI LogC4 specification.
- **`encodeSRGB`**: the sRGB transfer function (IEC 61966-2-1), linear → encoded, the inverse of the
  sRGB decode.
- **`planckianChromaticity`**: CIE 1931 xy of a Planckian radiator from the cubic-spline
  approximation of Kim et al. 2002, valid 1667–25000 K and clamped to it. EmulsionFixtures keeps its
  own copy (`SyntheticDNG.planckianChromaticity`) as an independent reference for the tests.
- **`bradford`**: Bradford chromatic adaptation between two white points (identity when equal).
- **`xyzToLinearSRGB`**: CIE XYZ → linear sRGB, the working space (Rec. 709 primaries, D65).

## SignalRange, YCbCrMatrix and VideoSignal

- Video code values are coded as ITU-R BT.2100 Table 9 states them, in 10-bit codes. Narrow
  ("video", legal) range: Y′ 64…940, Cb/Cr 64…960 around 512. Full range: Y′ 0…1023, Cb/Cr 0…1023
  around 512. Codes are normalized by the largest 10-bit code, 1023.
- `YCbCrMatrix` is the Y′CbCr → R′G′B′ matrix, by its luma weights (ITU-R BT.709 Table 3; BT.2020
  Table 4, BT.2020 / BT.2100 non-constant luminance). `toRGB` takes Cb and Cr centred on 0 (BT.2100
  Table 6 inverted).
- `VideoSignal(frame:)` takes the range from the frame's pixel format and the matrix from its tag, or
  the fallback matrix when the tag is missing or not one Emulsion reads.

## CurveInputTransform

Samples → each curve's formula input, as three affine rows fixed for a whole clip: the signal range,
the Y′CbCr matrix and the curve's code-value re-coding folded together, so the kernels do three dot
products per pixel. Applied by `samplesToWorking` in the kernel (rows `r0`, `r1`, `r2`) and by
`apply` in Swift. Samples are code × `YCbCrLayout.sampleUnitsPerCode`.

## YCbCrLayout

- The 10-bit bi-planar Y′CbCr pixel formats Emulsion reads without conversion. 4:2:0 halves chroma
  vertically as well as horizontally; 4:2:2 only horizontally.
- Samples are 16-bit with the 10-bit code in the high bits (CoreVideo `x420` family), so a sample is
  code × 64 / 65535.
- Planes become images on the luma grid with sample values untouched. Chroma is upsampled
  bilinearly, co-sited with even luma columns (BT.2020 / H.273 chroma location 0).
- Each plane is wrapped without copying; Core Image uploads it when rendering (zero-copy Metal
  textures belong with the frame source, MOV-39). The frame stays locked until Core Image releases the
  plane's data.

## ExposureAnchor

The exposure anchor (MOV-134): stops added to a RAW develop so that the tones the file's own DNG
profile (ProfileGainTableMap and ProfileToneCurve) renders at mid-gray sit at scene 0.18. 48 MP
ProRAW carries 2–3 stops of its brightening in the gain table, which the linear develop bypasses. The
anchor is an estimate that follows the profile, not a measurement of the scene.

- **Choice**: measured from the file, a value already known for it (`RenderService` reuses it per
  file), or none (tests and timings).
- **Thumbnails**: both renders are 256 px on the long edge, fixed so previews and exports get the
  same anchor.
- **Window**: pixels whose profile render is within ±1 stop of mid-gray choose the anchor. Below 1 %
  of the valid pixels in the window, every valid pixel counts instead. Luminance at or below 1e-6 has
  no usable ratio.
- **Range**: −2…+5 stops. Measured −0.56…+2.95 stops on 25 real DNGs; the clamp only stops a broken
  profile or a near-black frame from throwing the develop far off.
- **The estimate**: log2 of the geometric mean of Y(profile) / Y(linear) (Rec. 709 luminance) over
  the window, clamped to the range; 0 when no pixel has a usable ratio or the renders differ in size.
  Pixels are read back as float, so values above 1 and below 0 survive.
- **Reuse of the decode**: the context caches intermediates, so the profile render reuses the linear
  render's decode. Apple's own reuse between renders of one filter depends on what the process
  decoded before (on the iPhone 14 Pro, 12 Pro and Pixel files every render could decode again,
  MOV-134). Only `localToneMapAmount` and `boostAmount` are switched for the profile render: changing
  `boostShadowAmount` or `contrastAmount` too forces a new decode. The filter needs Apple's rendering
  bypassed, the thumbnail scale set and draft mode off, and is left with local tone map and boost at 0.

## LocalTone

Edge-aware Highlights and Shadows, carried over from the GradingCore local-tone study, where it
measured ≤ 1 code of halo against 17–22 codes for `CIHighlightShadowAdjust`.

- **Base**: perceptual lightness averaged over exact 16 × 16 blocks (padded grid, four 2 × 2
  halvings), upsampled with `CIEdgePreserveUpsampleFilter` guided by full-resolution lightness. The
  curve acts on the base; detail rides additively in lightness; one RGB ratio keeps hue.
- **Negative settings** (deepen shadows, brighten highlights) are scaled by 0.4 so the curve stays
  monotone: slope ≥ 1 − 0.4 · 2.2 > 0.

## CameraWhiteBalance

White balance of a RAW develop: the light the camera's neutral is set to, applied in the camera's
colour space by Apple's RAW decoder when the file is developed, before the film process. Separate
from the printer-light Warmth and Tint, which act at print. Photos that aren't RAW ignore it.
`temperature` is the kelvin of the light that develops neutral (a higher setting renders warmer);
`tint` is the offset from the Planckian locus (positive renders magenta, negative green). The ranges
are `CIRAWFilter.neutralTemperature` and `neutralTint` as Apple documents them in `CIRAWFilter.h`:
2000…50000 K and −150…150.

## RenderProcess and RenderIntent

- The engine model a recipe file names for a process. Film keeps the name it had before there were
  processes (`emulsion-default-v1`), so film recipes are byte-for-byte unchanged; an app that predates
  a process refuses its recipes (`recipeModelUnsupported`) instead of printing them as film. The
  controls of `Adjustments` mean different things in each process.
- The digicam process compresses only exports through its in-camera JPEG (a preview's 8 × 8 blocks
  would be sub-pixel); the film process renders both intents alike.

## InputContract

See `ENGINE.md`, "Input contracts". `sceneReferred`: scene light by a published decode (RAW developed
with Apple's look off, scaled by its BaselineExposure and the exposure anchor; camera log; linear).
`nominalScene`: scene-referred by its standard but usually rendered by the camera before encoding
(HLG); decoded as scene light, not claimed to be the scene. `displayReferred`: a finished picture made
for a display (JPEG, HEIC, Rec.709, Display P3) whose scene light can't be recovered, so the engine
re-renders it from an estimate. `previewEstimate`: a display-referred source whose scene estimate is
printed absolutely, to preview a scene-referred capture (the camera viewfinder); preview only, never
exported or stored.

## DigicamKernels

The digicam process's kernels (`Kernels/Digicam.ci.metal`) are linked into the same metallib as the
film kernels (`Tools/build-kernels.sh`). Each property is named like its Metal function, without the
`digicam` prefix.

# Test fixtures (EmulsionFixtures)

## SyntheticDNG

A deterministic synthetic DNG (TIFF/EP, little-endian, uncompressed, one strip, 16-bit) that Apple's
RAW decoder accepts. Camera values are linear, 1 = sensor white; values outside 0…1 clip, as a sensor
does. Nothing models a real camera: the colour matrices are synthetic.

- **Mosaics**: `bayerRGGB` has one sample per pixel behind an RGGB colour filter array
  (PhotometricInterpretation CFA, 32803; red at even/even, blue at odd/odd; CFAPattern indices 0 red,
  1 green, 2 blue). `linearRGB` has three demosaiced samples per pixel (DNG LinearRaw, 34892), the
  container ProRAW uses; LinearRaw needs DNGBackwardVersion 1.3.
- **Size**: width and height are even, so the RGGB pattern tiles the image.
- **Tags**: `asShotNeutral` is the camera-space neutral (green = 1, DNG AsShotNeutral);
  `cameraFromXYZ` is XYZ → camera, DNG ColorMatrix1 for CalibrationIlluminant1 = D65 (EXIF LightSource
  21). CIRAWFilter needs NewSubFileType, PhotometricInterpretation, StripByteCounts, DNGVersion,
  ColorMatrix1, SamplesPerPixel, AsShotNeutral, BaselineExposure and the CFA pattern (macOS 27.2).
- **Codes**: 16-bit with no black offset: code 0 is no light, 65535 sensor white.
- **Minimum file size**: ImageIO identifies a TIFF with DNGVersion as DNG only from about 100 KiB
  (macOS 27.2: 101,862 bytes read as TIFF, 102,886 as DNG), so files are padded with trailing zeros to
  128 KiB.
- **Profile**: a DNG profile's rendering hints, the tags Apple's 48 MP ProRAW uses to brighten its
  image. ProfileGainTableMap (DNG 1.6, so the file is then DNG 1.6) holds one gain everywhere: every
  pixel, whatever its level. ProfileToneCurve is (input, output) pairs from (0, 0) to (1, 1), linear in
  and out, identity by default. DefaultBlackRender 1: no automatic black subtraction, as in iPhone
  ProRAW.
- **Gain table stream**, in the file's byte order (DNG SDK `dng_gain_table_map::GetStream`):
  MapPointsV, MapPointsH (u32); MapSpacingV, MapSpacingH, MapOriginV, MapOriginH (f64); MapPointsN
  (u32); five MapInputWeights (f32: R, G, B, min, max; any choice gives the same uniform gain); then
  the gains (f32), N innermost.
- **TIFF writer**: one IFD (header, IFD, out-of-line values, the single strip, then zero padding);
  StripOffsets is filled in; offsets are word aligned; rationals use a denominator of 1,000,000 (six
  decimal places). Tags from TIFF 6.0, TIFF/EP and DNG 1.6.

### Synthetic cameras and illuminants

- `daylightNeutral` (0.48, 1.0, 0.62): a typical daylight sensor neutral; red and blue sites see less
  of a D65 white than green. Artistic.
- `xyzFromLinearSRGB`: IEC 61966-2-1 primaries; the Rec. 2020 matrix: ITU-R BT.2020 primaries.
- `sensorCrosstalk`: an artistic stand-in for overlapping sensor dye responses; rows sum to 1 so
  white stays white.
- `sRGBCameraFromXYZ` = diag(daylightNeutral) · XYZ→linear sRGB: a scene colour c in linear sRGB under
  D65 reads daylightNeutral · c exactly in camera space. Its gamut is sRGB, so it cannot record colours
  outside sRGB (they clip to 0 at the sensor).
- `wideGamutCameraFromXYZ` = diag(daylightNeutral) · crosstalk · XYZ→linear Rec. 2020: D65 white still
  reads daylightNeutral; Display P3 colours outside sRGB stay positive, so they survive the sensor.
- `planckianChromaticity`: CIE 1931 xy of a Planckian radiator, 1667–25000 K, Kim et al. 2002
  cubic-spline approximation of the Planckian locus.
- `d65Chromaticity` (0.3127, 0.3290): as the colour standards round it, the value
  `InputColorSpace.d65` uses. `illuminantAKelvin`: CIE standard illuminant A, a tungsten lamp, 2856 K
  (CIE 15:2004).

## RAWDevelopChart

The scene and synthetic files used to measure RAW develop (MOV-79): a half-stop neutral wedge from
−4 to +3.5 stops around mid-gray, followed by chromatic patches, two of them outside sRGB.

- With the default (wide-gamut) camera the top three wedge patches clip green at the sensor, and +3.5
  also clips blue.
- `outOfSRGBP3`: Display P3 colours with a negative linear sRGB component: P3 red at 0.9 (G −0.038,
  B −0.018 in sRGB) and a saturated green (R −0.118).
- The chromatic scene is the first six `SceneFixtures.patchesP3`, then `outOfSRGBP3`, in linear sRGB.
- `cameraValues(_:light:)`: each D65 camera value scaled per channel by the ratio of the two lights in
  camera space (von Kries in camera space), at the same luminance. Exact for neutral patches; for
  chromatic ones a simple model, not a spectral simulation.
- `dng`: AsShotNeutral is the camera neutral of `taggedLight`, the light the camera believed it saw.
  At the D65 defaults the stored neutral is `SyntheticDNG.daylightNeutral` to the six decimals the file
  keeps, so the file is the one the MOV-79 and MOV-134 measurements used.

## PatchChart, DisplayFixtures and VideoFixtures

- `PatchChart`: cells are large enough that demosaic and denoise edges leave each centre untouched;
  means are taken over each patch's central quarter (half width, half height).
- `DisplayFixtures`: finished pictures encoded in Display P3, as a JPEG or HEIC decodes. The proof
  chart, bottom row first: a 256-step gray ramp (one code per column), a near-white sky gradient rising
  to code 255 at the right edge, then two rows of patches (primaries, secondaries, saturated sky and
  coral, skin, and mid-saturation versions).
- `VideoFixtures`: synthetic 10-bit Y′CbCr movies of flat patches, written with AVAssetWriter and
  read back without conversion. HEVC Main10 is 4:2:0 and carries legal or full range; ProRes 422 HQ
  is 4:2:2 and legal range only (the writer converts full range). Both round-trip flat patches exactly
  in their native layout (`VideoSignalTests`). Patches are 64 px, a multiple of the codecs' block
  sizes, so each patch's centre is flat. The matrix tag is written to the file and comes back as the
  frame's `kCVImageBufferYCbCrMatrixKey`.

# The fitting tool (EmulsionFit)

## LeastSquares

Bounded nonlinear least squares: minimizes Σ rᵢ(p)² over lower ≤ p ≤ upper. Deterministic (no
randomness, no concurrency), so the same problem always gives bit-identical results.

- **Method**: Levenberg–Marquardt with Marquardt's diagonal damping (initial λ 1e-3 relative to
  diag(JᵀJ)) and Nielsen's gain-ratio update; bounds hold by projecting each step into the box, and a
  parameter on a bound whose gradient points outward is frozen for that step. When it stops without
  converging (iteration or damping limit, singular system), a bounded Nelder–Mead search restarts
  from its best point and Levenberg–Marquardt polishes once more.
- **Jacobian**: central differences, one-sided where a bound is closer than the step. The step is
  relative to max(|p|, 1): the cube root of machine epsilon (≈ 6e-6) balances truncation against
  rounding error (Nocedal & Wright, *Numerical Optimization*, 2nd ed., §8.1).
- **Convergence** (MINPACK's tolerances, all 1e-12): `costTolerance` (ftol) when both the actual and
  the predicted relative cost reductions fall below it; `stepTolerance` (xtol) when a step is shorter
  than this relative to |p|; `gradientTolerance` (gtol, a cosine) when every free Jacobian column is
  this close to orthogonal to the residuals. 500 iterations at most. Past a damping of 1e16 the damped
  step is too short to matter: the search has stalled. The predicted reduction is ‖r‖² − ‖r + J s‖².
- **Nelder–Mead**: the starting simplex spans 10 % of each parameter's box; at most 2000 evaluations
  per parameter; bounded by clamping every vertex into the box; standard coefficients (reflect 1,
  expand 2, contract and shrink ½); ties broken by vertex index, so the search is deterministic.
- **Standard errors** come from σ²·(JᵀJ)⁻¹ over the free parameters (those not on a bound, which are
  held fixed), with σ² = SSR / (n − p_free): they describe the scatter of the residuals around this
  model only, not the digitizing error of the data. None for a parameter on a bound, or for all of
  them when JᵀJ is singular or n ≤ p.

## NormalEquations

Symmetric positive-definite systems (least-squares normal equations) by Cholesky factorization,
A = L Lᵀ. Matrices are n × n arrays, row-major. Plain Swift on purpose: the systems have at most a
dozen unknowns, and Accelerate's current LAPACK interface would need an unsafe compiler flag in this
package. Fixed loop order, so results are bit-identical run to run (as for every vector helper in
`Array+Statistics`).

- A pivot (the squared diagonal of L) smaller than 1e-12 of A's largest diagonal entry means a column
  is, to about 12 significant digits, a combination of the earlier ones: the matrix counts as singular.
- `solveLeastSquares` minimizes Σ_n w_n·(Σ_i x_i·columns[i][n] − rhs[n])² through the normal equations
  (Σ w·a_i·a_j) x = Σ w·a_i·rhs; weights default to 1.
- The inverse is symmetric in exact arithmetic; it is averaged with its transpose to remove the
  rounding asymmetry.

## DyeSumCheck

Do the three dye spectra add up to the sheet's neutral spectrum? Compares a neutral against
a_Y·yellow + a_M·magenta + a_C·cyan with non-negative scales (least squares, or fixed) over the
wavelengths where every curve used is drawn. A check on the digitized spectra (MOV-17), not on the
engine. Dye densities are used as drawn, negative lobes included (the negatives' magenta dye dips
below zero near 445 nm).

- **Acceptance** (`acceptance(_:filmType:)`), target max |residual| ≤ 0.05 D (MOV-17):
  - camera negatives: neutral − minimum density against the fitted dye sum. The sheets draw the dye
    curves "D-mins subtracted" while the neutral and minimum-density spectra are drawn as measured;
  - print film: neutral against the fitted dye sum over 400–700 nm, where the three image dyes account
    for the visual neutral; below 400 nm the neutral rises steeply above the dye sum.
- Negatives draw a midscale neutral; the print film draws a visual neutral. `minimum_density` is the
  negatives' base + mask spectrum.
- **Diagnostics**, reported alongside the acceptance row and never asserted: the plain neutral for
  negatives; the full overlap and the scales-fixed-to-1 sum (the sheet says its dyes are normalized to
  the visual neutral) for the print film.
- **Best non-negative scales**: with three dyes every active set can be tried. The optimum of this
  convex problem is the unconstrained fit on some subset of dyes, so the best non-negative subset fit
  is exact.

## NegativeDyeSet

A camera negative's dye set, from its datasheet's spectral dye density chart, on a wavelength grid.

The sheet's cyan, magenta and yellow curves are "D-mins subtracted" and peak-normalized: each is the
net spectral density change per unit of dye formed, already including the coloured masking coupler
that forming the dye consumes (why magenta dips below zero near 445 nm, `FILM-THEORY.md` §3.3).
`minimumDensity` is base + fog + the unused masking couplers (the orange mask). For dye amounts
c = (cyan, magenta, yellow):

    D(λ) = Dmin(λ) + Σ_k c_k·ε_k(λ)

Between traced samples the curves are interpolated linearly; outside a curve's traced span its end
value is held (an assumption: the sheet doesn't draw there; `NegativeDyeSetReport` reports how much
zero-filling the dyes instead changes the results). The minimum density always holds its end values.

- **Densitometer**: the dye set read through one set of responsivities, with the minimum density's
  integral densities D_Π(0) computed once; `densityAboveMinimum` is D_Π(c) − D_Π(0) per channel.
- **Jacobian**: ∂D_i/∂c_k = Σ Π_i T ε_k / Σ Π_i T, with T the transmittance at the amounts. Rows are
  channels, columns dyes.
- **Solving for amounts**: Newton's method with the analytic Jacobian (each step solves
  JᵀJ δ = −Jᵀr, the Newton step for a square, nonsingular J); the spectral density is computed once
  per step, for both the residual and the Jacobian. Converged when every channel misses its target by
  at most 1e-10 D. From the previous neutral-scale sample's amounts Newton converges quadratically in a
  handful of steps; 50 iterations at most.

## SpectralResponsivities

The spectral responsivities Π_c(λ) of one density definition (Status M, a printing density), red,
green and blue, sampled on a wavelength grid. Integral density through them is ST 2065-2:2020 Eq. 1
(`FILM-THEORY.md` §2):

    D_c = −log10( Σ_λ Π_c(λ)·10^(−D(λ)) / Σ_λ Π_c(λ) )

The sums run over the grid; the constant Δλ cancels. The grid, 360–800 nm at 5 nm (the dye charts'
step), spans every table read: Status M from 410 nm, APD from 360 nm to 730 nm, the negatives' dye
charts to 800 nm.

## StandardsTables and StandardsManifest

The density definitions the dye-set checks integrate through, read from a local directory of
standards tables (`--standards`, else `EMULSION_STANDARDS_DIR`, else `standards` beside the reference
data, `~/Documents/Emulsion Research/standards` by default). Each file must match the SHA-256 in
`Resources/standards-manifest.json`, the committed provenance: per file, which standard, edition and
table it transcribes, where from, and the digest. The tables stay local (MOV-94).

- **Status M**: ISO 5-3:1995 Table 4 tabulates log10 spectral products, normalized to 5.000 at each
  channel's peak, at 10 nm. Interpolated linearly in log10 and extrapolated in log10 with the table's
  slopes (log10 per nm, below and above each channel's span) from the slopes file. The CSV has title
  rows before its ` nm,Red,Green,Blue` header.
- **APD**: SMPTE ST 2065-2:2020 element a, at 2 nm, linear between samples, zero outside.
- **RP 180**: SMPTE RP 180-1999 Table 1, at 10 nm, linear between samples, zero outside.

## NeutralScale

The negative's neutral scale read through its dye set. At every characteristic-chart sample (log10
lux-seconds, ascending, where every channel is traced) the Status M density above each channel's
lowest traced density fixes three dye amounts (Newton, from the previous sample's amounts); those
amounts then give the printing densities above minimum density. Each quantity can be read as a curve
for `NegativeFit.straightLineGamma`.

## PrintingDensityConversion

A linear conversion to printing density above minimum density, fitted by least squares, with its
residuals (printing density − fitted) reported per channel on the neutral scale and on a lattice of
dye amounts.

- `dyeAmounts`, PD ≈ P·c: printing density per unit dye.
- `dyeAmountsWithOffset`, PD ≈ P·c + b: the form the engine uses (`ConversionSet.engine`), with the
  neutral scale weighted by `engineNeutralScaleWeight`. The offset costs nothing in the engine: the
  calibrated printer lights absorb it.
- `statusM`, PD ≈ M·SM, and `statusMWithOffset`, PD ≈ M·SM + b: whether a 3 × 3 (plus offset) from
  Status M suffices, as ST 2065-2 NOTE 3 and RP 180 §3 suggest (`FILM-THEORY.md` gap G-1).
- **Fit sets**: `neutralScaleAndLattice` (colours as well as neutrals: what a conversion applied to
  every pixel needs) or `neutralScale` (neutrals only: how closely a 3 × 3 can follow the neutral scale
  alone). Residuals are always reported, unweighted, on both.
- **Lattice**: every combination of 9 evenly spaced amounts per dye from 0 to each dye's neutral-scale
  maximum, cyan slowest.
- **Neutral-scale weight**: each neutral-scale row is multiplied by w (w² in the normal equations);
  lattice rows by 1. The engine's matrix uses 10: the neutral scale sets tone and gray balance, so it
  should be followed closely. For 250D APD, at 10 the neutral-scale max residual falls to about
  0.006 D (0.017 unweighted) while the lattice RMS rises by at most 0.004 D; at 100 the lattice
  residuals grow several-fold for a further 0.002 D on neutrals. The reports compare weights 1, 10
  and 100.
- **Matrix** rows are printing density red, green, blue; columns are cyan, magenta, yellow amounts, or
  Status M red, green, blue.

## NegativeDyeSetReport

What `emulsion-fit dyes` computes for a camera negative from its digitized dye spectra and
characteristic curves, through the Status M, APD and RP 180 responsivities: the midscale
reconstruction (MOV-88 acceptance), the mask check, the neutral scale in dye amounts and printing
densities, straight-line gammas, and the printing-density conversions. Every number is computed from
digitized datasheet data, not measured on film. It encodes with sorted keys (as every report does,
`Encodable+Report`) so two runs write byte-identical files.

- **Midscale check**: 10 nm steps within 400–700 nm, where the image dyes dominate.
- **ADX**: Dmin-subtracted APD scaled by k = (1.00, 0.92, 0.95) for red, green, blue (ST 2065-3:2020
  Eqs. 1–2).
- **Conversions**: through APD (SMPTE ST 2065-2), which holds the engine's matrix, and through RP 180
  printing density. The set compared: each model on the neutral scale and lattice, the engine form at
  each `neutralScaleWeightSweep` weight, and the Status M fits on the neutral scale alone.
- **Mask check**: integral density of the minimum-density spectrum against the characteristic chart's
  lowest traced density; the chart is Status M, so only the Status M row compares like with like.
- **Gammas**: straight-line gammas (`NegativeFit.straightLineGamma`, the middle third of each curve's
  span), red/cyan, green/magenta, blue/yellow.
- **Edge diagnostic**: how much zero-filling the dye curves outside their traced spans, instead of
  holding the end values, changes the neutral scale: the largest absolute change of any channel at any
  sample, and of any entry of the engine's APD matrix.
- **Neutral-scale table** (CSV): `log_exposure_lux_s`, Status M, dye amounts, APD and RP 180 printing
  density above minimum, one row per sample. The Markdown summary (`NegativeDyeSetSummary`) holds
  the same numbers as the JSON report in short; its conversion table has the neutral-scale max, lattice
  RMS and lattice max per channel, one row per fit.

## DigitizedStock, StockManifest, DigitizedChart and StockDataAudit

- **DigitizedStock**: a stock's digitized datasheet charts and their manifest, validated on load. The
  manifest comes from a manifests directory (`<id>/manifest.json`, bundled with the tool); the traced
  CSVs, which are not published, come from the local reference-data directory (`<id>/<chart file>`:
  `--data`, else `EMULSION_REFERENCE_DATA`, else
  `~/Documents/Emulsion Research/datasheet-tracings`), and each must match the SHA-256 (lowercase hex)
  its manifest pins, checked before it is parsed, so a different file is reported as a mismatch.
- **StockManifest**: the fields of `manifest.json` the tool reads: the source document, the film type,
  and per chart its file and digest, sampling grid (0.05 log10 exposure or 5 nm), conditions, axis
  scales, traced extents (before resampling), interpolated stretches (x spans bridged across a gap in
  the drawn line), shared stretches (where a curve shares one drawn line with another, so the channels
  can't be told apart) and the one-sigma digitizing error per traced point. Other keys are ignored.
  Only camera negatives have a camera-stop axis; its origin is where camera stop 0 (normal exposure)
  sits on the log10 exposure axis. Loading checks the format version, that the manifest names its
  directory's stock, and that no number the checks divide by is unusable (a zero grid step or pixel
  scale would otherwise make the audit pass vacuously).
- **DigitizedChart**: a shared x column and one curve per remaining column; an empty cell means the
  chart doesn't draw that curve at that x. Curves interpolate linearly between samples (across
  untraced gaps too) and continue outside them by the end value or straight on with given slopes.
- **StockDataAudit**: checks beyond loading: samples on the digitizer's grid (within 1e-6 grid steps:
  parsing `-3.70` gives −74.000000001 × 0.05), inside the traced extent (the manifest rounds `xRange`
  to three decimals, and the digitizer resamples onto grid points up to half a pixel beyond the traced
  ends), and characteristic curves that never fall by more than one chart pixel of density below their
  running maximum: a tracing can't resolve less than a pixel (0.006 D on the 250D chart, 0.016 D on the
  2383 chart).

# Tests (EmulsionCoreTests, EmulsionFitTests)

Tolerances below are about twice the worst value measured on macOS 27.2, on Bayer and linear
synthetic DNGs unless the row says otherwise; the measurement is the source of each.

## Test tolerances

### CameraWhiteBalanceTests

| Constant | Value | Source |
| --- | --- | --- |
| `relativeFloor` | 0.01 | Relative to the larger of this and the reference value: chromatic patches have channels near 0. |
| `asShotTemperatureTolerance` | 15.0 | Measured worst 6.8 K (2862.8 K read for 2856 K; 6502.0 K for 6504 K). |
| `asShotTintTolerance` | 0.5 | Measured worst 0.25 from the expected tint (0.25 for 2856 K; 9.77 for D65, expected 9.52). |
| `taggedNeutralTolerance` | 0.0025 | Measured worst 0.0012 (max \|R/G − 1\|, \|B/G − 1\|) on the gray patches. |
| `wrongTagCast` | 1.0 | The wrongly tagged file as shot: measured worst neutral error 1.22; a cast at least this large. |
| `correctedNeutralTolerance` | 0.011 | Measured worst 0.0053 on the gray patches at 2856 K, tint 0. |
| `correctedMatchTolerance` | 0.037 | Measured worst 0.0183 (relative, any channel; chromatic patches, gray 0.0053) between the develop at 2856 K, tint 0, and the correctly tagged file: Apple reads that file as 2862.8 K. |
| `readBackMatchTolerance` | 0.012 | Measured worst 0.0056 (Bayer; linear 2.5e-5) at the temperature and tint read from the correctly tagged file. |
| `asShotRepeatTolerance` | 2e-5 | Measured worst 7.4e-6 (absolute, any channel and pixel) setting the as-shot values back. |
| `previewTolerance` | 0.002 | Measured worst 0.0009 (relative to max(1, value)), draft half size vs full. |
| `tintPerDuv` | 3000.0 | Apple's tint is the light's distance from the Planckian locus (Duv, CIE 1960 uv) × 3000, positive above the locus (green light, magenta correction): the scale of the DNG SDK's `dng_temperature` (\|kTintScale\| = 3000). Measured here, not documented by Apple. |

### ExposureAnchorDevelopTests

| Constant | Value | Source |
| --- | --- | --- |
| `identityAnchorTolerance` | 6e-4 | Measured worst 3.0e-4 stops (12 MP-like, identity curve). |
| `pairAnchorTolerance` | 2e-6 | Measured worst 8.1e-7 stops: 48 MP-like anchor − 12 MP-like anchor − 2. |
| `pairValueTolerance` | 4e-4 | Measured worst 2.1e-4 (relative, any channel, any patch) between the two anchored develops. |
| `sceneTolerance` | 0.003 | Measured worst 0.0014 (relative to the larger of 1 and the value, any channel) against the scene. |
| `toneCurveShiftTolerance` | 5e-4 | Measured worst 2.2e-4 stops: tone-curve anchor shift against log2(0.7). |
| `scalarTolerance` | 2e-6 | Measured worst 6.4e-7 (relative) per pixel and channel: anchored ÷ un-anchored against 2^anchor. |
| `scalarFloor` | 1e-3 | Pixels this close to zero have no meaningful ratio. |

### RAWDevelopTests

| Constant | Value | Source |
| --- | --- | --- |
| `linearTolerance` | 0.005 | Measured worst 0.0024 (relative, any channel, BaselineExposure 0 and 2; headroom patch 0.0016). |
| `neutralTolerance` | 0.0045 | Measured worst 0.0021 (max \|R/G − 1\|, \|B/G − 1\|) on unclipped neutrals. |
| `clippedNeutralTolerance` | 0.045 | Measured worst 0.0222 (+3 stop patch: green clipped, blue rebuilt 2 % high). |
| `chromaticTolerance` | 0.0035 | Measured worst 0.0016 (absolute, any channel, chromatic patches, linear sRGB). |
| `previewTolerance` | 0.0025 | Measured worst 0.0012 (relative to max(1, value), draft half size vs full). |
| `headroomBaselineStops` | 3.0 | Exposure that puts the brightest unclipped neutral (camera 0.72) at 5.76, above 4.0. |

### ExposureAnchorRealFileTests

| Constant | Value | Source |
| --- | --- | --- |
| `appleMedianTolerance` | 1.15 | Measured worst \|log2(anchored median ÷ Apple median)\| 0.576 stops over 25 files (mean 0.168). |
| `megapixelGapTolerance` | 0.5 | Measured −0.017 stops: mean log2(anchored ÷ Apple) of files ≥ 40 MP minus files < 20 MP (before the anchor the 48 MP ProRAW files sat 2–3 stops below Apple's render). |

### CameraWhiteBalanceRealFileTests

| Constant | Value | Source |
| --- | --- | --- |
| `asShotRepeatTolerance` | 4e-4 | Measured worst 1.6e-4 (any channel and pixel, relative to max(1, value), 1024 px; absolute 0.0024 on a file anchored +2.95 stops) setting the as-shot values back. |

### RAWDecoderTests

| Constant | Value | Source |
| --- | --- | --- |
| `backToAsShotTolerance` | 2e-6 | Back at as shot after another white balance, against the file's own untouched neutral: measured 6.0e-7 on the linear file and 9.5e-7 on the Bayer one (about 2× the worst). |

### RAWDevelopRealFileTests

| Constant | Value | Source |
| --- | --- | --- |
| `maxTolerance` | 0.01 | The old develop's max may exceed the new one only by rounding. |


## CameraWhiteBalanceTests

RAW white balance (MOV-10) on synthetic DNGs of the wide-gamut camera: a chart lit by a 2856 K
Planckian light, tagged with that light or wrongly with D65. The independent reference is the
light's Planckian chromaticity (Kim et al. 2002); D65's CCT is 6504 K (CIE 15:2004). Duv is measured
in CIE 1960 uv. A tungsten scene the camera tagged as daylight must develop neutral once told the
light was 2856 K, and like the correctly tagged file, chromatic patches included. On a "48 MP-like"
profile file the exposure anchor is measured at the as-shot white balance, so it is the same whatever
white balance develops the image. Re-saved real files whose AsShotNeutral is [1, 1, 1] only test the
mechanism, not the camera's white balance.

## ExposureAnchorDevelopTests

The anchor through `Developer.develop` on synthetic DNGs whose profile carries a gain table and a tone
curve, which CIRAWFilter applies (macOS 27.2) as it does for real ProRAW. Both files hold the same
camera values: a "48 MP-like" profile (BaselineExposure 0.5, gain × 4) and a "12 MP-like" one
(BaselineExposure 2.5, gain × 1) render the same picture, so their anchored develops must agree; both
put the chart's scene at its linear sRGB values.

- The darkening tone curve is TC(m) = 0.7 m up to 0.9, so it covers the whole window, chromatic
  patches included. It has points every 0.05: the profile tone curve is interpolated with a cubic
  spline, which longer segments bow (one segment to 0.9 moved the anchor 0.032 stops; points every 0.1
  by 0.008).
- The anchor is one multiply: every pixel and channel (chromatic, above 1, negative) scales by
  2^anchor.
- A develop given an anchor an earlier develop reported (`RenderService` reuses it per file) skips the
  thumbnails: at full size it matches the measuring develop exactly; a preview may then decode in
  draft mode, which the measuring develop doesn't (measured worst 0 on these files, macOS 27.2), so it
  gets the draft preview's tolerance.

## RAWDevelopTests and RAWDevelopSupport

RAW develop on synthetic DNGs (MOV-79): linear scene light with highlight headroom, neutral clipped
highlights and no gamut mapping, for Bayer and linear (ProRAW-container) files.

- Expected values come from the fixture's own maths: the sensor clips to 0…1, the as-shot neutral maps
  to D65 white (the matrix's calibration illuminant), and BaselineExposure scales the result.
  "Unclipped" neutrals stay below 95 % of sensor white in every channel.
- A highlight that reaches 4.0 in scene light (`headroomFloor`) is two stops above the old ceiling
  of 1.0.
- A ProRAW file that ImageIO types as TIFF when read from memory must still develop as RAW: only real
  files show that (`RAWDevelopRealFileTests`). The DNG type hint the Developer passes exists for them.
- A draft RAW decode may come back larger than asked, so preview tests only bound its size.
- These tests measure Apple's decode as the develop configures it (`RAWDevelopSupport.develop` reads
  `RAWDecoder.decode`), at float precision. The develop itself is that decode in a half-float buffer
  (MOV-147); `developIsTheDecodeInHalfFloat` bounds the difference (`halfFloatTolerance` 0.002
  relative, floor 0.01: measured worst 9.5e-4, about one half-float step, 2^-10).
- The pre-MOV-79 configuration (`applyPreMOV79Develop`) is frozen for before/after comparisons:
  Apple's look processing off, gamut mapping, shadow bias and highlight recovery at the file's
  defaults. Real files are decoded at a 1024 px long edge to keep 48 MP files fast.
- `RAWDecoderTests` (MOV-137): a decoder kept alive for interactive white balance develops exactly
  what a develop from the file does. `Developer.develop` is itself one negative of a decoder, so the
  reference for as shot is a `CIRAWFilter` nothing has set a neutral on. It is exact at every white
  balance; back at as shot it is within the return tolerance, which the exposure anchor scales with
  every value.
- `ExposureAnchorRealFileTests` (MOV-134): anchored develops land near Apple's default render (every
  `CIRAWFilter` default) in median luminance, whatever the file's megapixels.

## RAWDevelopProbe

Measures how Apple's `CIRAWFilter` develops synthetic DNGs (MOV-79): scale, clipping, EDR, gamut
mapping, highlight recovery, decoder versions and white balance. It prints tables and asserts nothing
about Apple's behaviour. Opt-in: `EMULSION_RAW_PROBE=1`; `EMULSION_RAW_PROBE_DUMP=<dir>` also writes
the wedge DNGs there.

- `decoderAndContexts` follows FB24419261 (cited by Apple DTS): a tint with the 9.dng decoder under a
  custom working space.
- Report labels only: a clipped patch within 2 % of neutral prints as "neutral", and a patch counts as
  still rising when it is over 1 % brighter than the one below it.
- White balance: CIE daylight chromaticity is CIE 15:2004 eq. 3.3–3.4, defined for 4000–25000 K only.
  The gray patch is reported with its OKLab distance (× 100) from a neutral of equal luminance. The
  tungsten scene is camera-space von Kries: exact for the gray patch, an approximation for chromatic
  ones.
- Real files: the three with the highest scaled-decode maximum also get a full-size decode (maximum on
  the GPU, as they are too large to read back). The raw layout readout parses the TIFF structure (IFD
  chain and SubIFDs) for the full-size raw IFD (NewSubFileType 0, PhotometricInterpretation CFA 32803
  or LinearRaw 34892). Highlight colour is the mean R/G and B/G of the brightest 0.1 % of pixels by
  luminance. White balance is probed on the two lowest as-shot temperatures (tungsten interiors) and
  the two closest to 5500 K (daylight).

## RAWDevelopProofRenders and DisplayReferredProof

Before/after PNGs through the neutral film look for the PRs (MOV-79, MOV-134, MOV-10), into
`EMULSION_PROOF_DIR`. Real files: only CC0 samples (names ending in `_CC0.dng`) are rendered, at a
640 px long edge so each PNG stays a few hundred KB. The exposure-anchor pair is the develop without
and with the anchor; the white-balance set is the tungsten chart tagged as daylight, as shot and at
2856 K, with the correctly tagged file as the reference, and the CC0 files as shot, cooler (× 0.75)
and warmer (× 1.35). `DisplayReferredProof` writes PNG renders of the display-referred proof chart and
prints a table of numbers into `EMULSION_PROOF`.

## DigicamTests

The digicam process (MOV-149). The GPU is compared with the Swift mirror in encoded 0…1 at the centre
of each 8 px block (corner softness at this size is far below a pixel). The measured numbers and the
owner's directions behind them (noise σ, sharpening overshoot, the tungsten cast) are in
`DIGICAM.md`. The corners must never be sharper than the lens-softened centre: at low processing the
corner blur (× processing) is below the whole-frame lens blur, and once left the corners crisper. A
white balance set at develop is applied on top of the camera's cast: the negative still reports the
as-shot light, so the residual cast follows the light the photo was shot under.

## FullSizeRenderTests

Full-size renders of real DNGs (MOV-147, `ENGINE.md` "RAW decode corruption"), opt-in because only
real files corrupt. Each file is rendered 4 times with the default look and full halation: the
develop's own render, and a deliberately hostile one (the develop read through
`insertingIntermediate(cache: false)` and rendered by a context that doesn't cache intermediates).
Each is compared tile by tile (256 px, `tileSize`) with a reference decoded at contrast 0 (the
develop's is 1e-4), alone, through a caching context: an independent decode on Apple's other
path, which measured clean there. `tileTolerance` is 3 codes of mean |Δ| per channel: clean tiles
measured at most 1.3 codes, corrupt ones 15–134. Exports must also repeat bit for bit. On CI,
`developNeverSetsContrastToZero` checks the develop's contrast setting on a file that supports it,
`everyRAWDevelopIsAnOwnedBuffer` that every RAW develop is a half-float buffer,
`everyRenderCachesIntermediates` the context setting, and `viewfinderRendersOnlyCameraFrames` that
the viewfinder's uncached context only takes a camera frame's preview estimate, in either render
process.

## ExportTests

Exported files read back through ImageIO, independently of the engine: format, ICC profile, bit depth,
orientation, size and the Display P3 values. Video export doesn't exist yet (MOV-126). The red patch
is outside sRGB, so a file tagged or converted as sRGB would come back clipped. Blocks are large and
flat so chroma subsampling and compression leave their centres alone, and wider than tall so a
swapped orientation shows up. Largest code-value error at a block centre, in 8-bit steps, measured on
Xcode 27.2 at quality 0.95: JPEG 0.88, HEIC 0.18 (8-bit rounding alone is up to 0.5). The camera
JPEG is stored landscape, tagged "rotate 90° clockwise to view", with a GPS position: the export must
be upright (the develop already rotated the pixels) and carry no location.

## VideoSignalTests

AVAssetReader blocks its thread while decoding, and many parallel readers starve the Swift
concurrency pool (observed deadlock), so the suite is serialized. ProRes has no full-range coding, so
it is tested in legal range only. Core Image's own Y′CbCr → R′G′B′ conversion of the same frame (no
colour matching, decoded as linear Display P3 so the comparison is on the signal) is an independent
check of the range and matrix conventions: legal range agrees within 1e-5; in full range Core Image's
chroma is about 0.1 % wider than BT.2100's (D − 512) / 1023 (2e-4 of signal on the chromatic patch).
Emulsion follows BT.2100, as colour-science does. A wrong range misses by far more than the
tolerance: legal and full coding agree at code 446 (64 + 876·E′ = 1023·E′), so gray patches near it
barely move, but white (codes 572–721) lands 20+ codes off; neutral patches don't depend on the
matrix, the chromatic one does.

## Colour references

- `ColorReferenceTests`: the input transforms against colour-science, with chromatic samples so a
  wrong gamut matrix can't hide behind gray. The GPU sample codes are each formula's own input, so
  they are decoded in `formulaRange`; re-coded into the other range they decode to the same light
  (MOV-80). Sub-black policy (`ENGINE.md`): every decode is monotonic through black, so a sub-black
  signal never decodes brighter than code 0 (MOV-125 found HLG doing exactly that).
- `ColorSpaceTests`: each curve's published 18 % gray code value decodes to 0.18; LogC4 checks
  decode(encode(0.18)) from the published encoding; Rec.2020 red lies outside sRGB.
- `ToneTests`: 18 % gray → 0.17 display-linear ≈ code 114.
- `ColorTests`: a scene-linear magenta → red neon ramp pushed into the highlight shoulder. Every tone
  scale compresses highlights, so colour steps are judged against the neutral scale's own
  compression at the same brightness: colours must not merge faster than gray does.

## ColorDifference, StructuralSimilarity and the regression harness

- `ColorDifference`: CIEDE2000 (kL = kC = kH = 1, Sharma, Wu & Dalal 2005) on Display P3 encoded
  output, checked against colour-science and the paper's data (`References/delta-e.json`). The Lab
  white is the display's own D65 and no chromatic adaptation is applied: both images compared share
  that white. CIE 1976 lightness companding: ε = 216/24389, κ = 24389/27. Percentiles are
  nearest-rank, sorted[⌈p·n⌉ − 1], computed in integers so no rounding can move the rank; the 99.9th
  is what is left after ignoring the worst pixel in a thousand.
- `StructuralSimilarity`: SSIM (Wang, Bovik, Sheikh & Simoncelli, IEEE TIP 13(4), 2004) on CIE L*,
  with the paper's constants: an 11 × 11 Gaussian window of σ 1.5 px, K1 0.01, K2 0.03, dynamic range
  L 100. Written from the paper with vImage convolutions; no third-party code. Single scale: the photo
  goldens are 240 px on the long edge, too small for the five halvings of MS-SSIM. The mean is over the
  pixels whose whole window lies inside the image (as the paper and scikit-image do). Against
  scikit-image 0.26 (`References/ssim.json`) the largest difference measured is 2e-6 (this
  implementation works in Float).
- `RegressionImage`: renders are read back like the Renderer's own context (extended linear sRGB,
  half float) and stored as 16-bit Display P3 RGB PNGs, big-endian samples, top row first. Core Image
  quantises and clips. 16-bit samples without an explicit order are big-endian (the Quartz default).
- `SceneFile`: frozen scenes are half-float RGBA TIFF (LZW, lossless) in the working space, read back
  without colour matching. Not OpenEXR: ImageIO's EXR writer converts through ColorSync in float and
  moves half floats by a few ulps (0 became −4e-5 next to 11.5), so it cannot freeze a scene exactly.
- `RealScene`: real photographs frozen as developed, downscaled (CC0 only, `Scenes/PROVENANCE.md`).
  Freezing keeps the look suite independent of the OS RAW decoder and of develop work in flight;
  `Developer.develop` itself is covered by the local tier. Each scene is decoded once per process.
- `ReportFiles`: `report.md`, `report.json`, `update-summary.md` and per-case actual / golden / diff
  (a ΔE00 heat map) images. Only files a previous run wrote are removed: the directory may be one the
  user named.

## Banding

A step is a band when it is both visible on its own and much larger than the steps around it, which is
what the eye picks out as an edge in a gradient. A ramp whose steps are all equally coarse (an 8-bit
source lifted by an edit) is quantisation, a known limit of 8-bit sources, not a band; a plateau
followed by a jump (contouring) is one, because the plateau's steps are near zero.

| Constant | Value | Source |
| --- | --- | --- |
| `minimumVisibleStep` | 1.0 ΔE00 | About one just-noticeable difference between adjacent samples. |
| `neighbourRatio` | 3.3 | Measured (`BandingTests`): the worst step on `main` and on the −6-stop floor of #50 is 2.63× its neighbours (blue ramp, shadows +1, codes 0→1); the MOV-25 defect (#50 at a −9-stop floor) is 4.20× (blue) and 4.24× (gray). 3.3 is about their geometric mean. |
| `neighbourhood` | 4 | Steps on each side. |
| `flatNeighbourhood` | 0.05 ΔE00 | A neighbourhood median below this counts as this, so a flat run (a plateau, or clipped white) does not divide by zero: a step after it is judged by `minimumVisibleStep` alone. |
| `largestLightnessDrop` | 0.5 ΔL* | A larger drop on a rising ramp is a fold, reported as a band. Measured worst on every ramp: −0.010. |

## GrainStatistics

Grain measured the way film granularity is: fluctuations of density on a uniformly exposed patch.
Here the density is the rendered print's visual density, −log10 of its display luminance (relative to
display white; floored at 1e-6, so black reads as density 6), not a Status A or diffuse density of a
real print.

- RMS granularity σ(D): the standard deviation of density on the patch. Kodak and ISO 6328 measure it
  through a 48 µm aperture; here it is per pixel, so values depend on resolution.
- Noise power spectrum (Wiener spectrum): mean of |FFT|² / tile² over every whole 64 × 64 tile, each
  with its own mean removed, radially averaged, in density² · pixel². Bins are k / 64 cycles per pixel
  for k = 0…32; corner frequencies beyond 0.5 cycles per pixel are left out. Its mean over every
  frequency is the variance (Parseval), so the spectrum shows how σ(D)² spreads over grain sizes.
- `highToLowPower`: power at 0.375–0.5 cycles per pixel over 1/64–0.125 (the zero bin excluded): about
  1 for white noise, smaller for grain that spans several pixels.

## ReviewRenders

See `Tests/AGENTS.md`, "Perceptual checks". The default look uses a fixed grain seed so a before/after
pair differs only by the engine; "digicam-strong" is noise 1 and processing 1. The file is kept free
of other test-target helpers because `Tools/review-renders.sh` copies it into an older checkout when
that checkout does not have it (one older than the digicam process, MOV-149, can't build it).

## EmulsionFitTests

- `StockDataTests`: manifest checks always run; checks on the traced curves, which are not in the
  repository (`DECISIONS.md`, 12 Nov 2026), run only when the local reference-data folder exists.
  The datasheet PDFs are recorded in `STOCK-DATA.md` (stock id → document, SHA-256). With cyan clamped
  at 0, yellow and magenta solve their own normal equations: [[2,1],[1,2]]·a = [2, 3.5].
- `ManifestValidationTests`: a zero grid step or pixel scale would otherwise let the audit pass
  vacuously; each traced CSV must be the one its manifest pins, checked before parsing, so a different
  file is a mismatch even when it wouldn't parse. JSON can't carry a non-finite number, so that case
  is built in code. The fixture directory serves as both the manifests and the reference-data folder.
- `LeastSquaresTests`: the bounded case has the unbounded optimum (3, −2) in a box allowing p₀ ≤ 1 and
  p₁ ≥ −1; a zero gradient at the start makes the damped system singular (plateau ending at 0.2); the
  line fit checks SE(slope) = σ / √Σ(x − x̄)²; a parameter held on its bound counts as fixed, so its
  standard errors and degrees of freedom match the model without it.
- `NormalEquationsTests`: A = [[4, 2, 2], [2, 5, 3], [2, 3, 6]] is positive definite; with
  x = [1, −2, 3], b = A x = [6, 1, 14]. The singular case's third row is the first plus the second.
