# Emulsion engine

Emulsion is a film lab for colorists. It takes camera RAW, log and HDR video, and ordinary JPEG/HEIC/MP4. RAW and log are decoded into **scene light**; HLG is decoded as nominal scene light; ordinary JPEG/HEIC only gets an estimate of scene light, because the phone's rendering can't be undone, and is printed relative to itself (see [Input contracts](#input-contracts)). The result is printed through a modeled photochemical system. The look comes from a negative → print chain behaving like one. It is not a stack of filters or a LUT.

The UI should stay simple, while the engine underneath is something a colorist can trust: it's measured, its stages are documented, and the GPU output is verified against a reference model.

## Architecture

```
source ──▶ input transform ──▶ scene light (linear, 0.18 = mid-gray) ──▶ grade ──▶ film system ──▶ output
          RAW develop         one working space for every source          exposure   negative → print   P3 today;
          log / HLG curves                                                  halation   printer lights     Rec.709 2.4,
          display estimate                                                  local tone grain              PQ/HLG next
```

| Stage | File | What it does |
| --- | --- | --- |
| RAW develop | `Developer.swift` | Apple `CIRAWFilter` with Apple's rendering switched off: no boost, local tone map, extra contrast, extended dynamic range, gamut mapping or shadow bias. Gamut mapping was what capped highlights near 1.0, so turning it off keeps their headroom and lets out-of-gamut colours stay negative for the film model. Highlight recovery stays on, so clipped channels are estimated and blown highlights stay neutral. The result is demosaiced, white-balanced, linear scene light scaled by the file's BaselineExposure (MOV-79). ImageIO types many ProRAW files read from memory as plain TIFF, so files are identified, and handed to `CIRAWFilter`, with a DNG type hint |
| Input transforms | `ColorSpaces.swift`, `VideoSignal.swift`, `inputTransform` / `ycbcrInputTransform` kernels | Apple Log, S-Log3/S-Gamut3.Cine, ARRI LogC3/LogC4, V-Log, DaVinci Intermediate/DWG, ACEScct (Bradford from ACES white), HLG (BT.2408 scaling), Rec.709 and Display P3 display encodings. Code values become the BT.2100 signal E′ using the declared range (legal or full); 10-bit Y′CbCr frames use their tagged matrix (BT.709 or BT.2020). S-Log3, LogC3 and V-Log formulas take 10-bit legal-range code values, the rest take E′ |
| Display-referred sources | `FilmModel+Display.swift`, `displayToScene` and `filmSystemRelative` kernels | JPEG/HEIC/Rec.709/Display P3 get a scene estimate through the film's own neutral print response, with soft ends so display white and black land on a finite ceiling (+4 stops) and floor (−9 stops). At render time the change the film predicts for the user's edits is applied to the photo itself, so zero edits reproduce it and edits act like the film would on that estimate. It is a re-render, not a recovery of the scene (see Input contracts) |
| Film system | `FilmModel.swift`, `filmSystem` kernel | Layer sensitivities (crosstalk) → negative H&D curves → printer lights → print H&D curves (Richards toe) → print dye cross-absorption → 10^−density relative to paper white. Mid-gray is calibrated neutral, like a timing lab |
| Highlight chroma retention | same | The one non-physical step. Bright saturated light (neon) blends toward a ratio-preserving render above +1.5 stops, so it doesn't band. Midtones are unaffected; timed (warm/cool) neutrals above +1.5 stops lose part of their timing, and very bright saturated colors stay tinted instead of reaching white (artistic choice under review) |
| Halation | `Renderer.swift` | Scene highlights above about +3.5 stops add red-orange glow (core + skirt) back into exposure, before the negative. Blurred at reduced scale with energy-preserving box halving |
| Local tone | `LocalTone.swift` | Halo-free Highlights/Shadows: a box-averaged base layer with edge-preserving upsampling (carried over from the GradingCore study; the current test allows ≤3 codes of halo) |
| Grain | `grain` kernel | Density noise on perceptual lightness, peaking in the midtones. The cell size is relative to the image, and sub-pixel cells are attenuated, so preview and export carry matching grain statistics |
| Interactive speed | `Renderer.materialize` | The developed preview is rendered once into a half-float buffer, so slider moves never re-run the RAW develop or the JPEG inversion |

## Input contracts

Not every input can tell us what the scene looked like. Each source has a contract: what its decoded values mean, and what the engine may say about them. In code the contract is `InputContract`, declared by each input on `InputColorSpace.contract` and carried by every developed image on `Negative.contract`.

| Source | Contract | What the engine does | What it may claim |
| --- | --- | --- | --- |
| RAW (Bayer DNG, ProRAW) | Scene-referred | Apple `CIRAWFilter` with Apple's look switched off | Linear scene light from Apple's develop. ProRAW is already computational photography, so "scene light" means Apple's linear develop, not a sensor measurement. Highlight headroom is MOV-79 |
| Camera log (Apple Log, S-Log3, LogC3/LogC4, V-Log, DaVinci Intermediate, ACEScct) and linear P3 | Scene-referred | The manufacturer's published curve and gamut matrix | Scene light; the decode is verified against colour-science references |
| HLG (Rec.2100) | Nominal scene | BT.2100 inverse OETF with BT.2408 scaling | Decoded as scene light by the standard, but phone HLG is rendered by the camera before encoding, so it is not claimed to be the scene |
| JPEG, HEIC, Rec.709, Display P3 | Display-referred | Scene estimate from the neutral print response (soft ends at the top and bottom), then printed relative to the photo | A re-render of the photo, not the scene. Zero edits reproduce it: gray codes 0–255 within 1 code (measured 0.06), a real 8-bit JPEG of mild chroma within 0.25 codes of its own decode (measured 0.07). For colors near the P3 boundary the output gamut fit lowers chroma, to 94% at the primaries (OKLab ΔE×100 up to 2.1; on a saturated gradient a low channel rose by up to 10 codes); lightness and hue are kept. Display white is estimated at +4 stops, black at −9 stops; the ceiling, the floor and the two knees (display-linear 0.75 and 0.006) are engineering choices, not measurements. Limits: edits act on an estimate; the Color control acts more weakly on extremely saturated source colors; 8-bit sources still quantize; HDR headroom is discarded (MOV-49); halation is driven by the estimate, so a clipped white glows like a +4-stop light (peak glow source 0.72, computed from the halation source at the estimate; the earlier unbounded inverse gave about 4) |
| Camera viewfinder frames (the camera's processed video) | Preview estimate | `Developer.viewfinderNegative(from:)`: the display-referred scene estimate, approximated by a 1D curve sampled once from the Swift mirror (built-in `CIColorCurves`, 1024 steps in extended Display P3 encoding) and the inverse layer sensitivity (`CIColorMatrix`), with no per-pixel solve; then printed absolutely, like the RAW capture it previews | A preview of the RAW render made from the camera's processed video frame, never scene light. Its print is within OKLab ΔE×100 0.04 of printing the exact estimate (`ViewfinderEstimateTests`). How far it is from the captured photo (Apple's video tone mapping, white balance, noise reduction, clipping) is unmeasured until device testing (MOV-121). Preview only: never exported or stored |
| HDR stills (gain-map HEIC/JPEG, PQ/HLG HEIF) | Display-referred | Read as their SDR rendition (the gain map is ignored; PQ/HLG are tone-mapped by Core Image), then as above | Same as display-referred; HDR headroom is discarded until MOV-49 |

**Sub-black policy.** Decoding keeps sub-black signals (legal-range footroom, compression undershoot) as negative light; clipping is the film model's job. Where a specification defines values below its range, the engine follows it: Apple Log holds at R₀, and the log curves' toes and sRGB's linear segment extend linearly. Where it doesn't (BT.2100 HLG, BT.1886 gamma 2.4), the curve is extended oddly (mirrored), so every decode stays monotonic through black. colour-science mirrors HLG the same way; for BT.1886, which colour-science clamps, the reference generator applies the engine's convention.

## Stock files

A stock's parameters live in a JSON stock file, not in code. `FilmStock` (`FilmStock.swift`) is the file format; `FilmModel(stock:)` turns it into the immutable model the renderer and kernels use.

- **Format** (`formatVersion` 1): `name`; `provenance` (`source`, `notes`, and optional `fitDate`, `tool`, `sourceSHA256`, `fitResiduals`, omitted when absent); `negative` (`sensitivity` 3×3, `gamma`, `densityRange`, `exposureOffset`); `print` (`gamma`, `minimumDensity`, `densityRange`, `shape`, `dyes` 3×3); `rendering` (`highlightChromaRetention`, `middleGrayOut`). Matrices are three rows of three, row-major. Gammas are density per log10 exposure; offsets are log10 exposure relative to mid-gray. `encoded()` writes sorted keys, so a stock always encodes to the same bytes.
- **Validation** (`EmulsionError.invalidStock` with the reason): unknown `formatVersion`, wrong array lengths or missing keys; non-finite numbers; gammas, density ranges or print shape ≤ 0; negative minimum density; `middleGrayOut` outside (0, 1); `highlightChromaRetention` outside [0, 1]; sensitivity or dye rows not summing to 1 (±1e-6; that is what keeps neutrals neutral); and a print the printer lights can't time, meaning mid-gray misses `middleGrayOut` by more than 1e-6. `errorDescription` is the plain localized sentence; the reason is `failureReason`.
- **Default:** `Resources/Stocks/emulsion-default.json`, hand-tuned and not fitted to any datasheet, loaded once as `FilmLook.stock`. A test pins its render bit-for-bit to the engine before stock files existed.

## Digitized stock data

The offline `EmulsionFit` target (never linked into an app, not a library product) holds a manifest per digitized stock in `Sources/EmulsionFit/Resources/StockData/<stock>/`, naming the PDF (with its SHA-256), page, conditions, axis calibration, the per-point reading error and the SHA-256 of each traced CSV, plus the fitted stock files (see "Fitting stocks"). The traced curve CSVs are not in the repository (`docs/DECISIONS.md`, 12 Nov 2026): anyone with the public PDF can re-trace them with `Tools/stock-digitizing/digitize.py`. They are local reference data, read from `EMULSION_REFERENCE_DATA` or else `~/Documents/Emulsion Research/datasheet-tracings`; the loader refuses any CSV whose digest differs from its manifest. Where that folder is missing, only the manifest checks run. `docs/STOCK-DATA.md` ("Digitized curves") covers the method, the error estimates and the cross-check.

- **Manifest checks on load:** the manifest's `stock` must match its directory, and grid steps, pixel scales, uncertainties, x ranges, spans and the camera-stop anchor must be finite and in range, or loading fails naming the field.
- **Audit:** samples sit on the manifest's grid and inside each curve's traced extent, and characteristic curves never fall by more than one chart pixel of density.
- **Dye-sum check** (MOV-17): the yellow, magenta and cyan dye spectra, with non-negative least-squares scales, against the sheet's neutral; target max |residual| ≤ 0.05 D. Dye densities are used as drawn, negative lobes included (the negatives' magenta dye dips below zero near 445 nm). Negatives: the acceptance compares neutral − minimum density, because the dye curves are drawn "D-mins subtracted" while the neutral and minimum-density spectra are drawn as measured; the unsubtracted comparison is reported as a diagnostic. Print film: the acceptance compares the visual neutral over 400–700 nm, where the three image dyes account for it; the full overlap and the scales-fixed-to-1 residual (with its mean) are diagnostics. With scales fixed to 1 the neutral sits above the plain dye sum by a roughly flat amount over 400–700 nm and rises steeply below 400 nm; the chart does not say what the extra density is.

## Fitting stocks

`emulsion-fit` (target `EmulsionFit`, offline only, never linked into an app) fits stock parameters to the digitized datasheet charts described above. It reads the manifests (bundled, or `--manifests <dir>`) and the traced curves from the reference data (`--data <dir>`, else `EMULSION_REFERENCE_DATA`, else the default folder); `check` and `negative` stop with an error when there is none.

- **Committed fits:** `StockData/<stock>/negative-fit.stock.json` for 250D and 500T, written by `emulsion-fit negative --stock <id> --out <dir> --fit-date 2026-11-12` (default base and name). They hold parameters, provenance (including the characteristic CSV's SHA-256) and residual statistics only; the fit report and plot table contain traced samples and stay local. A test refits from the reference data and checks the file is reproduced byte for byte. Shared-range RMS against the traced curves: 0.0261 D (250D) and 0.0252 D (500T); per-layer range 0.0213 and 0.0210.
- **Not used by the engine yet:** the bundled default stock (`emulsion-default`) is unchanged and not fitted. The fitted files sit in the offline target until MOV-25 decides how fitted stocks are bundled (under neutral ids).

- **What is fitted today:** only the negative characteristic curves. Per layer, density = minimum density + `FilmModel.negativeDensity` (the engine's own curve, not a copy) of log10 exposure minus a mid-gray anchor. Two parameterisations are always run: a shared density range (10 parameters; the one written to the stock file, since `FilmStock.Negative` holds one range) and a per-layer range (12; diagnostic for MOV-25). Everything else in the written stock is the base stock's hand-tuned values.
- **Frame:** density in the chart's densitometry (Status M for the camera negatives) against the chart's log10 exposure in lux-seconds. The mid-gray anchor defaults to camera stop 0 on the chart, an approximation; it shifts the exposure offsets but not the fit quality. Minimum densities (base + fog + mask) are fitted but not stored: the calibrated printer lights absorb a constant per-layer density.
- **What the numbers mean:** RMS and max residuals (measured − fitted density) say how closely the engine's symmetric logistic follows the *traced* curves; mean residuals per exposure third show systematic shape misfit. Standard errors are fit statistics, σ²·(JᵀJ)⁻¹; none of these numbers include the digitizing error (manifest `uncertainty`; docs/STOCK-DATA.md, "Digitized curves") or how the publisher drew the chart. A good fit to a datasheet curve is not a measurement of film.
- **Minimum density on its bound:** the fitted value is then not a reading of the film's base density (the logistic's long toe absorbs it); the report, summary and stock notes say so and give the lowest traced density. Each layer also reports its straight-line gamma (least-squares slope over the middle third of its traced density span) next to the logistic's centre slope.
- **Acceptance and caveats in the report:** the 0.03 D RMS target is MOV-106's for 250D only (`NegativeFitReport.targetStock`); other stocks are compared with it, not judged. Each layer reports how many fitted samples lie in the manifest's interpolated or shared-line spans (fitted with full weight, not dropped). Standard errors count only the parameters not on a bound (σ² = SSR / (n − p_free)).
- **Stock name:** the written stock is named `"<base name>, fitted negative"` (or `--name`); the datasheet and publisher stay in provenance, never in the name (MOV-92).
- **Solver:** plain Swift (Cholesky for the normal equations, at most 12 unknowns), so the package needs no unsafe compiler flags and stays usable as a remote dependency.
- **Determinism:** no randomness and sorted-key JSON, so the same data gives byte-identical stock files and reports (`--fit-date` is the only date written).

## Verified behavior (synthetic tests, `swift test`)

Tests, all passing:
- the GPU film system matches the Swift model within 0.6 codes on 200 colors;
- printed 18% gray is neutral, and the neutral response is monotone over 20 stops;
- skin keeps its hue family from −2 to +1 stops;
- bright colors lose chroma without abrupt desaturation (they don't fully reach white: see highlight chroma retention);
- neon light degrades no faster than gray at the same brightness;
- halation is local, red-biased and resolution-independent;
- grain is zero-mean, strongest in the midtones, deterministic per seed, and matches between preview and export;
- display-referred photos (P3 code values and a real JPEG) are reproduced at zero edits: gray codes 0–255 within 1 code on every channel, saturated colors within 5° of hue and 0.02 OKLab lightness; at −3 EV the gray ramp stays monotone with steps of at most 3 codes, including the top codes; the scene estimate is bounded (white at most +4 stops, black at −9); exposure darkens every gray code and has no slope jump at zero edits (±0.02 stops within 4%), desaturating a primary raises its zero channels, a clipped white still glows red-orange, halation stays finite, and the GPU matches the Swift mirror;
- the viewfinder's preview estimate prints within OKLab ΔE×100 0.036 (max) / 0.007 (mean) of printing the exact display estimate on a 4096-step gray ramp, 0.029 / 0.007 on P3 primaries, secondaries and the display patches, and 0.032 / 0.010 on a saturated hue sweep; the gray estimate itself is within 0.003 stops; out-of-range light is clamped like the kernel and alpha is kept; a preview estimate prints exactly like scene light, and no input or develop produces one;
- every input declares its contract, and the developed negative keeps it (log, HLG and Display P3 code values, a JPEG, and through materialize and resize);
- local tone doesn't halo;
- the materialized negative keeps highlight headroom;
- RAW develop (synthetic Bayer and linear DNGs, MOV-79) is linear: unclipped neutrals land on camera value ÷ AsShotNeutral × 2^BaselineExposure within 0.5 % (measured 0.24 %) and stay neutral within 0.45 % (measured 0.21 %); a patch expected at 5.76 develops to 5.76, so highlights keep their headroom above 1.0; clipped neutrals rebuilt by highlight recovery stay within 4.5 % of neutral (measured 2.2 %); chromatic patches match the camera-matrix value within 0.0035 (measured 0.0016), and Display P3 colours outside sRGB keep their negative component; the draft half-size preview matches the full develop within 0.25 % (measured 0.12 %); and the film render of a developed chart with values above 4 and below 0 stays finite and within the display range;
- a plain TIFF is not developed as RAW (the reverse, ProRAW that ImageIO types as TIFF still developing as RAW, is checked on real files only);
- exports are Display P3, with HEIC at 10-bit;
- every camera log decodes its published 18% code to 0.18;
- gamut matrices keep neutrals neutral;
- the GPU input transform matches colour-science on every input, including display negatives and superwhite, in legal and full range;
- visual regression (MOV-37): fixed renders (synthetic patch rows and spatial scenes, a display-referred chart, two frozen CC0 photos) stay within mean 0.2, p95 0.5, max 1.0 ΔE00 (CIEDE2000 on the 16-bit Display P3 output) of goldens the engine itself produced (local tone on the two photos: p99.9 in place of max, because a few isolated pixels differ between GPUs). It detects change, it does not prove correctness; +0.1 stop of exposure or warmth 0.2 on the chart already fails it;
- 10-bit HEVC (legal and full range) and ProRes 422 HQ (legal) frames of S-Log3, LogC3, V-Log, Apple Log and HLG decode their gray, white and a chromatic patch to colour-science within the reference tolerance (2e-4 relative); a wrong range or matrix assumption fails, and the Y′CbCr conversion agrees with Core Image's own (within 1e-5 legal; full-range chroma differs by ~0.1%, Emulsion follows BT.2100).

Real-file RAW checks are opt-in (`EMULSION_RAW_SAMPLES`; the samples never enter the repo). On 25 DNGs (22 iPhone 15 Pro Max, one each from iPhone 14 Pro, iPhone 12 Pro and a Pixel 8 Pro Bayer sensor), every developed value is finite, no file's maximum went down, and the five files with BaselineExposure above 3 now reach 7.8–13.3 where they used to stop near 1.0. Whether fused ProRAW data is itself linear in scene light can't be tested with these files (no chart or grey card) and is unverified. Numbers per file: the `proof/mov-79` branch.

Tone scale of the stock, in output codes:

| Exposure | −8 | −4 | −2 | 0 (18% gray) | +2 | +4 | +6 stops |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Output code | 5 | 17.5 | 45 | 114.5 | 202 | 242 | 252 |

Speed on an Apple-silicon Mac GPU, full pipeline:

| Size | Time |
| --- | ---: |
| 1600 px preview | 6.7 ms |
| 12 MP | 20 ms |
| 48 MP | 96 ms |

Display-referred photo (developed and materialized once, render only; Mac, three runs, range of medians). Measured alternately with the code before this change: look only is about 10% slower at 12–48 MP, the full pipeline about 5–10%:

| Size | Look only | Full |
| --- | ---: | ---: |
| 1600 px preview | 1.5–2.3 ms | 4.0–6.0 ms |
| 12 MP | 7.1–8.2 ms | 17.9–20.9 ms |
| 48 MP | 37.6–45.8 ms | 87.8–94.2 ms |

**Device numbers are still needed.**

## Roadmap, in order of colorist value

1. **Output transforms.** Explicit display encodings: Rec.709 BT.1886 2.4, sRGB, P3-D65 2.6, and HDR Rec.2100 PQ/HLG rendered from the film state before the SDR clip (re-expanding an already-clipped print shoulder doesn't work).
2. **Video.** AVAssetReader / AVPlayerItemVideoOutput pixel buffers enter as raw code values (no color matching) → input transform → Renderer → AVAssetWriter (HEVC 10-bit, ProRes 422). Add gate weave and flicker as optional temporal texture.
3. **LUT export.** Bake input transform → film system → output transform into 33³/65³ `.cube` LUTs for Resolve/Baselight/Premiere. Spatial effects (grain, halation, local tone) can't be LUTs and are listed as excluded.
4. **Stocks from public data.** Fit the negative and print model parameters to Kodak's published datasheet curves (Vision3 250D/500T characteristic and spectral-sensitivity curves; 2383 print), with a fitting report. Add lab controls: push/pull, printer-light points, print density, bleach-bypass (silver retention).
5. **Colorist tools.** True RAW white balance (Kelvin/tint in camera space via `CIRAWFilter`); RAW 9 decoder when available; acutance (edge contrast) and aura; scopes (waveform, parade, vectorscope) driven from the same render.
6. **UI.** SwiftUI with iOS 26 Liquid Glass. Simple by default: one look, Light / Color / Texture. Depth on demand. Native iPhone Duo layouts once Xcode 27.1 is installed.

## What we deliberately don't do

- No copying of another product's looks, data, code or branding. Chromagraph and Filmbox are references for *what* colorists value, not sources.
- No claims of matching any specific film or product without a measured comparison.
