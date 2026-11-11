# Emulsion engine

Emulsion is a film lab for colorists. It takes camera RAW, log and HDR video, and ordinary JPEG/HEIC/MP4. RAW and log are decoded into **scene light**; HLG is decoded as nominal scene light; ordinary JPEG/HEIC only gets an estimate of scene light, because the phone's rendering can't be undone (see [Input contracts](#input-contracts)). The result is printed through a modeled photochemical system. The look comes from a negative → print chain behaving like one. It is not a stack of filters or a LUT.

The UI should stay simple, while the engine underneath is something a colorist can trust: it's measured, its stages are documented, and the GPU output is verified against a reference model.

## Architecture

```
source ──▶ input transform ──▶ scene light (linear, 0.18 = mid-gray) ──▶ grade ──▶ film system ──▶ output
          RAW develop         one working space for every source          exposure   negative → print   P3 today;
          log / HLG curves                                                  halation   printer lights     Rec.709 2.4,
          inverse display                                                   local tone grain              PQ/HLG next
```

| Stage | File | What it does |
| --- | --- | --- |
| RAW develop | `Developer.swift` | Apple `CIRAWFilter`, with Apple's look switched off (no boost, no local tone map, no extra contrast): demosaiced, white-balanced, linear scene light |
| Input transforms | `ColorSpaces.swift`, `VideoSignal.swift`, `inputTransform` / `ycbcrInputTransform` kernels | Apple Log, S-Log3/S-Gamut3.Cine, ARRI LogC3/LogC4, V-Log, DaVinci Intermediate/DWG, ACEScct (Bradford from ACES white), HLG (BT.2408 scaling), Rec.709 and Display P3 display encodings. Code values become the BT.2100 signal E′ using the declared range (legal or full); 10-bit Y′CbCr frames use their tagged matrix (BT.709 or BT.2020). S-Log3, LogC3 and V-Log formulas take 10-bit legal-range code values, the rest take E′ |
| Display-referred sources | `displayToScene` kernel | JPEG/HEIC/Rec.709/Display P3 are inverted through the film system's own neutral response, so they are re-printed rather than having film stacked on top of Apple's rendering. The result is an estimate of scene light, not a recovery: low-saturation colors round-trip well, strongly saturated colors darken (see Input contracts) |
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
| JPEG, HEIC, Rec.709, Display P3 | Display-referred | Inverted through the film system's neutral response, then re-printed | An approximate re-render, not the scene. Measured round trip today: OKLab ΔE×100 mean 0.85 at 25% saturation, 3.3 at 50%, 14.5 at 100%, mostly darkening; top codes 253, 254 and 255 map to +6.6, +7.8 and +12 stops. MOV-82 replaces this inversion |
| HDR stills (gain-map HEIC/JPEG, PQ/HLG HEIF) | Display-referred | Read as their SDR rendition (the gain map is ignored; PQ/HLG are tone-mapped by Core Image), then as above | Same as display-referred; HDR headroom is discarded until MOV-49 |

**Sub-black policy.** Decoding keeps sub-black signals (legal-range footroom, compression undershoot) as negative light; clipping is the film model's job. Where a specification defines values below its range, the engine follows it: Apple Log holds at R₀, and the log curves' toes and sRGB's linear segment extend linearly. Where it doesn't (BT.2100 HLG, BT.1886 gamma 2.4), the curve is extended oddly (mirrored), so every decode stays monotonic through black. colour-science mirrors HLG the same way; for BT.1886, which colour-science clamps, the reference generator applies the engine's convention.

## Verified behavior (synthetic tests, `swift test`)

Tests, all passing:
- the GPU film system matches the Swift model within 0.6 codes on 200 colors;
- printed 18% gray is neutral, and the neutral response is monotone over 20 stops;
- skin keeps its hue family from −2 to +1 stops;
- bright colors lose chroma without abrupt desaturation (they don't fully reach white: see highlight chroma retention);
- neon light degrades no faster than gray at the same brightness;
- halation is local, red-biased and resolution-independent;
- grain is zero-mean, strongest in the midtones, deterministic per seed, and matches between preview and export;
- display-referred tone survives the inverse/forward round trip;
- every input declares its contract, and the developed negative keeps it (log, HLG and Display P3 code values, a JPEG, and through materialize and resize);
- local tone doesn't halo;
- the materialized negative keeps highlight headroom;
- exports are Display P3, with HEIC at 10-bit;
- every camera log decodes its published 18% code to 0.18;
- gamut matrices keep neutrals neutral;
- the GPU input transform matches colour-science on every input, including display negatives and superwhite, in legal and full range;
- 10-bit HEVC (legal and full range) and ProRes 422 HQ (legal) frames of S-Log3, LogC3, V-Log, Apple Log and HLG decode their gray, white and a chromatic patch to colour-science within the reference tolerance (2e-4 relative); a wrong range or matrix assumption fails, and the Y′CbCr conversion agrees with Core Image's own (within 1e-5 legal; full-range chroma differs by ~0.1%, Emulsion follows BT.2100).

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
