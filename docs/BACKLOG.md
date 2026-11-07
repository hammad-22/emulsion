# Emulsion backlog (draft for Linear)

Each item is meant to be one Linear issue: small, testable, with acceptance criteria. The prefix is the proposed Linear project; `→` lists dependencies. Priorities: **P0** blocks progress, **P1** core quality, **P2** important, **P3** later.

The product strategy is **Easy now, Pro later, same engine.** Every engine control exists in the engine API from day one; the easy app exposes a few, the Pro app exposes all.

---

## ENG-R · Research & reference data
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| R1 | Collect Kodak/Fujifilm public datasheets (Vision3 50D/250D/200T/500T, 2383/2393 print, Portra/Ektar C-41) | P1 | PDFs archived with source URLs; license note per document |
| R2 | Digitize datasheet curves: characteristic (D–logE) and spectral sensitivity, per layer | P1 → R1 | CSVs at 5 nm / 0.05 logE; plot overlays vs the source within 1 px; digitization method documented |
| R3 | Digitize dye spectral densities (negative + print) | P1 → R1 | CSVs; Status M/A densities recomputed within 0.02 of datasheet values |
| R4 | Literature notes: DIR couplers / interimage effects, Status M vs A densitometry, print viewing flare | P2 | One doc with citations and model equations we'll use |
| R5 | Clean-room review of agx-emulsion's published approach (GPLv3: ideas only, no code) | P2 | Written summary of techniques; explicit "no code copied" note |
| R6 | Colorist interviews: 5 colorists, what makes film emulation trustworthy | P1 | Notes + ranked feature list feeding ENG-G/APP |
| R7 | Reference image set: synthetic charts + licensed real RAW/log/HLG clips (incl. ColorChecker, skin range, neon, sky) | P0 | Versioned set with licenses; used by every visual regression |

## ENG-S · Spectral film model (the core quality jump)
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| S1 | Spectral upsampling of scene RGB (Jakob–Hanika 2019, own implementation) | P1 | Round-trip RGB→spectrum→RGB error < 1e-3 over sRGB/P3; tests |
| S2 | Layer exposure from spectra × measured spectral sensitivities | P1 → R2, S1 | Replaces 3×3 crosstalk; neutral at mid-gray after calibration; tests |
| S3 | Bake spectral exposure into a 3D LUT (log-encoded scene input) for real-time GPU use | P1 → S2 | GPU vs CPU spectral reference < 0.5 code; LUT ≤ 65³ |
| S4 | Negative characteristic curves fitted to datasheet D–logE per stock | P1 → R2 | Fit RMS < 0.03 density; fitting report |
| S5 | Dye densities → print exposure spectrally (negative dyes × print sensitivities) | P1 → R3, S2 | Print exposure computed spectrally, baked to LUT; tests |
| S6 | Print stock model fitted to 2383/2393 datasheets; viewing as projection with flare | P1 → S5 | Matches datasheet D–logE; neutral scale documented |
| S7 | DIR coupler / interimage model (density-dependent inhibition between layers, incl. spatial edge effect) | P2 → S4 | Saturation and edge-contrast behavior measured on charts; on/off toggle |
| S8 | Stock library: 4 negatives × 2 prints at launch, each with a fitting report | P1 → S4, S6 | Each stock passes neutral, monotone and skin tests |
| S9 | Keep the parametric model as a "fast/compat" path and as the GPU-vs-reference test oracle | P2 | Both paths tested against each other where comparable |

## ENG-T · Texture physics
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| T1 | Grain v2: per-layer, density-driven grain (Newson et al. Boolean model as reference; fast approximation on GPU) | P1 | Statistics (σ vs density, power spectrum) within 10% of the Monte-Carlo reference at 3 densities |
| T2 | Grain by gauge (8/16/35/65 mm) via relative grain size vs frame | P2 → T1 | Visual + statistical tests per gauge |
| T3 | Halation v2: physically sized by base thickness, red-layer dominant, threshold in exposure | P2 | Radius scales with gauge; tests |
| T4 | Aura (no anti-halation backing glow) | P3 → T3 | Toggle + test |
| T5 | Acutance / adjacency effects (developer exhaustion edge contrast) | P2 → S7 | Edge MTF lift measured; no halos > 2 codes |
| T6 | Gate weave + flicker (video only), seeded and deterministic | P2 → V3 | Amplitude spectrum matches spec; frame-exact repeatable |
| T7 | Dust/scratches (optional, Pro) | P3 | Procedural, seeded |

## ENG-IO · Color management
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| IO1 | Output transforms: Rec.709 BT.1886 2.4, sRGB, P3-D65 (2.2/2.6), DCI-P3 | P0 | Explicit encode kernels; reference values per standard |
| IO2 | HDR outputs: Rec.2100 PQ and HLG with highlight "unroll" to a nit target | P1 → IO1 | 1000-nit target; SDR/HDR consistency test at mid-gray |
| IO3 | More camera inputs: RED Log3G10/RWG, Canon Log 2/3, BMD Film Gen5, Fuji F-Log2, DJI D-Log, Nikon N-Log, Samsung Log, ACEScg | P2 | Published mid-gray tests per curve (like current suite) |
| IO4 | Gain-map HDR stills (Apple + ISO 21496-1) as scene-light input | P1 | Synthetic gain-map fixture: headroom recovered; SDR identity at zero edit |
| IO5 | ProRAW/DNG: true RAW white balance (Kelvin/tint in camera space), RAW 9 decoder when available | P0 | Fixture tests; white balance moves the camera neutral, not printer lights |
| IO6 | Gamut compression on input (wide-gamut log, e.g. neon in S-Gamut3) before film | P2 | No hue flips on out-of-gamut test patches |

## ENG-G · Grading controls (engine API; easy UI shows a subset)
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| G1 | Exposure / RAW WB / printer lights (points, Kodak convention) | P0 | Done partially; printer-point units tested |
| G2 | Lab controls: push/pull process, print density, bleach bypass (silver retention) | P1 → S8 | Each tested on charts |
| G3 | Whites/Blacks, Highlights/Shadows (local tone ✅), Contrast in density space | P1 | No halos; monotone |
| G4 | Color mixer (hue/sat/lum per band) in scene space before the negative | P2 | Smooth bands; skin protection optional |
| G5 | Three-way color balance (lift/gamma/gain or log offset/power/slope, ASC CDL compatible) | P1 | CDL round-trip with Resolve values |
| G6 | Curves (luma + RGB) in log/density space | P2 | Monotone constraints |
| G7 | Masks: subject/sky/person (Vision) with refine edges; per-mask grading | P3 | Pro |
| G8 | Look presets = stock + print + lab + texture snapshot, versioned | P1 | Codable; migration tests |

## ENG-P · Performance & quality infrastructure
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| P1 | Device benchmark harness (iPhone/iPad, 12/48 MP, 4K video frames) | P0 | Numbers in CI artifacts |
| P2 | Kernel fusion: one-pass look (input→film→output) where possible | P1 | ≥ 30% faster on device |
| P3 | Metal-backed live preview (CIRenderDestination, no CGImage copies) | P0 | 120 Hz slider drag at screen size on iPhone Pro |
| P4 | Visual regression suite on R7 (golden images + ΔE thresholds) | P1 → R7 | Runs in CI; diffs as artifacts |
| P5 | CI (GitHub Actions on macOS): swift test + kernel build + lint | P1 | Green on main |
| P6 | Memory budget for 48 MP and 4K video (tiling, intermediates) | P1 | Peak < 1 GB on device |

## VID · Video
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| V1 | Frame source: AVAssetReader/AVPlayerItemVideoOutput as raw code values (no color matching) | P0 | Synthetic log clip decodes to known values |
| V2 | Real-time playback with grade (Metal) | P0 → V1, P3 | 4K 30 fps on iPhone Pro |
| V3 | Export: HEVC 10-bit, ProRes 422/HQ, H.264; HDR metadata | P1 → IO2 | Tags verified with AVFoundation |
| V4 | Per-clip input detection from metadata (Apple Log, HLG, Rec.709) | P1 | Tests on fixtures |
| V5 | Temporal grain (new pattern per frame, seeded) | P1 → T1 | Repeatable per frame number |
| V6 | Trim + simple timeline (Pro later) | P3 | |

## LUT · Interop
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| L1 | Export .cube 33/65 (input→film→output; spatial effects excluded and listed) | P1 → IO1 | Resolve-loaded LUT matches the engine within 1 code |
| L2 | Export Resolve/Baselight-friendly look packages (README + LUT per output) | P2 → L1 | |
| L3 | Import .cube as a "custom print" | P3 | |

## APP · Easy app (SwiftUI, iOS 26 Liquid Glass)
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| U1 | Design system: glass components, typography, haptics, motion | P1 | Component gallery screen |
| U2 | Library: import photos/videos (RAW, HEIC, JPEG, MOV, MP4), grid, viewer | P0 | |
| U3 | Easy editor: Look (stock) picker + Light / Color / Texture, compare, reset | P0 → G8 | Usability test with 5 people |
| U4 | Export & share (Photos, Files), auto-export setting | P1 | |
| U5 | Onboarding that explains film looks in 3 screens | P2 | |
| U6 | Accessibility (VoiceOver labels, Dynamic Type) | P1 | Audit passes |

## CAM · Camera
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| C1 | RAW capture (ProRAW, Bayer RAW fallback), lens switch, tap focus/exposure | P1 | Device tested |
| C2 | Apple Log / HLG video capture | P2 | |
| C3 | Camera Control button + volume-button shutter | P2 | |

## DUO · iPhone Duo
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| D1 | Install Xcode 27.1 (needs ~25 GB free) + Duo simulator | P0 | Blocked on disk space |
| D2 | Adaptive layouts: ArrangementView split (viewer + controls) on the inner display | P1 → D1 | Simulator screenshots |
| D3 | Reserved regions (fold) respected; vertical toolbars | P1 → D1 | |
| D4 | Camera: direction coordinator, outer-display capture accessory | P2 → D1 | Device test |

## PRO · Pro version (same engine)
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| X1 | Pro control surface: every engine parameter, grouped like a film lab | P3 | |
| X2 | Scopes: waveform, RGB parade, vectorscope, false color (exposure in stops) | P2 | Computed from the render, GPU |
| X3 | Node-style or layered grades | P3 | |
| X4 | macOS app (shared EmulsionCore) | P3 | |
| X5 | OFX/plugin feasibility study for Resolve | P3 | Report |

## OPS
| ID | Title | P | Acceptance |
| --- | --- | --- | --- |
| O1 | Free disk space on the dev Mac (Trash 23 GB) | P0 | ≥ 30 GB free |
| O2 | Initial commit + GitHub repo (private) | P0 | User approval |
| O3 | Third-party notices + license audit (no GPL code) | P1 | |
