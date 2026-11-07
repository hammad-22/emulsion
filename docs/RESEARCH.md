# Emulsion: engine research report

**Audience:** product, design and engineering. No color-science background needed; every term is explained in the glossary at the end.
**Date:** 28 October 2026 · **Status:** research findings + recommended plan · independently fact-checked twice; the second was a deep adversarial review (see `docs/REVIEW-2026-10-28.md`), and its corrections are applied · **Engine version reviewed:** `b560b6a`

---

## 1. One-page summary

**What we're building.** Emulsion is a photo and video app for people who love the look of cinema film. It should be simple enough for anyone but trusted by professional colorists. Later, a Pro version will expose every control. Both versions run on **one engine**, and that engine is the product.

**What makes the engine different.** Most "film look" apps lay a filter or LUT over the phone's already-finished picture. Emulsion converts RAW photos and camera log footage back into the light the camera saw. Ordinary JPEGs can only be approximately re-rendered, because the phone's own processing can't be undone (see the Codex review, 29 Oct). Then it **simulates the film process**: the light exposes a film negative, the negative is printed onto print film, and the print is projected. Color, contrast, glow and grain all come out of that simulation instead of being painted on.

**Where we are.**
- **Film simulation.** The engine exists, is fast, and passes 20 automated quality checks: near-neutral grays, smooth highlights, stable skin tones, film grain and highlight glow (halation).
- **Speed.** On an Apple M4 Max Mac (32-core GPU), a 1600×1200 preview *renders* in about 6–7 ms. That excludes putting it on screen. A 48 MP image renders in about 0.1 s before file encoding. iPhone GPUs are several times slower; the review estimates about 30 ms per preview (not measured), so iPhone numbers are needed before we promise anything.
- **Inputs.** It reads Apple Log, Sony, ARRI, Panasonic, DaVinci and ACES footage using each manufacturer's published math.
- **Not yet verified on real material.** Every test so far uses synthetic images. No real RAW photo or log clip has been run, and we have no iPhone performance numbers yet.
- **Known input-correctness gaps (found in review, to fix first):**
  - RAW decoding probably clips highlights above 1.0 (`extendedDynamicRangeAmount = 0`; Apple's header says 0 means no extended range).
  - Video legal/full signal range isn't handled.
  - Apple Log 2 (iPhone 17 Pro) is missing.
  - JPEG/HEIC highlights posterize when re-printed.
  - Integer grain seeds all produce the same grain.

**The seven findings that matter most:**
1. **Kodak publishes the data needed for a far more realistic film model:** the color sensitivity of each film layer, the dyes each layer forms, and the contrast curves. Our current model approximates these; the next version should be built from them. This is the biggest quality upgrade available.
2. **The best way to use that data is a "spectral" simulation.** It's too slow to run live, but it can be pre-computed into a lookup table that is fast. The math methods are published and free to implement.
3. **Our print stage is softer than Kodak's print film.** Comparing peak slope with peak slope, 2383 is about 1.6–1.8× steeper. But a naive refit alone would make the whole look far too contrasty, raising mid-gray display gamma from about 1.24 to about 1.8–2.0. It has to be done together with a printing-density negative and projector flare, as one tone-reproduction refit.
4. **The red glow around lights (halation) depends on a specific film choice.** Modern cinema film has a backing that blocks it. The glow appears when that backing is removed. It should be an artistic switch, not always on.
5. **Real film is sharper in some colors than others, and colors push against each other chemically.** These "organic" details are measurable from Kodak's data. They're what separate convincing emulation from a filter.
6. **Grain depends on brightness and on each color layer.** A published physics model of grain gives us a ground truth to test our fast version against. A video standard (AV1) shows how to make grain efficient for video.
7. **The market is more crowded than first assumed.** Dehancer already ships a native iOS 26 app (iPhone and iPad) with log profiles and video editing. The physically based spektrafilm simulator now ships free in darktable, vkdt and a Resolve plugin. "Physically modeled" alone is not a moat. Our differentiation has to be proven through quality, ease and workflow, with a teardown of competitors on device and with interviews. To win colorists we must speak their language: printer points, standard color spaces, LUT export.

**Recommended next steps** (details in §5; revised after review):
1. Fix input correctness first: RAW highlight headroom, video signal range, Apple Log 2, JPEG inversion, the grain seed bug.
2. Measure on an iPhone and bake the color path into a lookup table now.
3. Run a competitor teardown on device and talk to users and colorists.
4. Do a combined tone-reproduction refit (negative + print + flare) and add display outputs.
5. Build the data-driven spectral film model, validated against a real film test shoot.

---

## 2. How film makes a picture (plain language)

Think of film as a three-stage factory. Our engine copies each stage.

1. **Capture (the negative).** Color film has three stacked layers, each sensitive to one kind of light: blue, green or red. Light from the scene builds an invisible image in each layer. The layers' sensitivities **overlap**, so some green light also registers in the red layer, for example. That overlap is one reason film colors look different from digital.
2. **Development.** Chemistry turns each layer's invisible image into colored dye. Brighter scene light makes more dye. The relationship between "how much light" and "how much dye" is the layer's **characteristic curve**. A camera negative has a very gentle curve: it records a huge range of brightness (Kodak's Vision3 chart spans 16 stops, and the curve responds over roughly 12 or more of them), which is why film handles bright skies well. During development, chemicals released in one layer slow down development in the others (**interimage effect**). That makes colors more saturated and edges crisper.
3. **Printing and projection.** The negative is printed onto **print film**, which has its own three layers, its own curves (much steeper, to create rich contrast and deep blacks) and its own dyes. The lab can add more or less red, green or blue light during printing; these steps are called **printer points**. This is how colorists balanced color before digital. Finally, the print is projected or viewed.

Along the way there's texture. **Grain** comes from the dye forming in tiny clumps. **Halation** is a glow around bright lights, caused by light bouncing off the back of the film. **Sharpness** differs slightly per layer.

**Why this matters for the product:** if the engine simulates these stages, every photo behaves consistently, the way real film does. In our synthetic model probes, overexposed skin drifts toward pale gold and bright skies slightly toward cyan. That's a measured model behavior, not yet validated on real photos or against real film. The goal is a coherent "film" instead of a filter that breaks on difficult photos.

---

## 3. What the engine does today

| Stage | Today | Plain-language effect |
| --- | --- | --- |
| Input | RAW (Apple's processing turned off), Apple Log, S-Log3, ARRI LogC3/LogC4, V-Log, DaVinci Intermediate, ACEScct, HLG, JPEG/HEIC | Every source becomes "the light the camera saw" |
| Film | Parametric 3-layer negative → print model, calibrated so gray stays neutral | Film-like color and tone |
| Bright neon | One deliberate exception keeps bright saturated lights from flattening | Neon signs don't turn into flat blobs |
| Texture | Halation, grain, halo-free highlights/shadows | Organic texture without digital artifacts |
| Output | Display P3 stills: JPEG (8-bit) and HEIC (10-bit) | Wide-gamut iPhone output |

**Measured** (synthetic images, Mac GPU):
- The GPU result matches the reference math within 0.6 of one 8-bit step, but only for mildly saturated colors. The gamut-mapping step (`fitP3`) has no reference implementation yet.
- Gray stays near-neutral (OKLab chroma < 0.03) from −6 to +6 stops, and exactly neutral at mid-gray.
- Every camera log decodes its published mid-gray code to 0.18 within 0.02%. Apple Log and LogC4 are checked by round-trip.
- Render times (Apple M4 Max, 32-core GPU; warm medians, render plus readback, no encoding): about 4–7 ms at 1600×1200, 19–20 ms at 12 MP, 92–96 ms at 48 MP.

**Known gaps:**
- No real-photo or real-video validation yet.
- The film model is hand-tuned rather than built from Kodak data.
- No video pipeline yet; output is limited to Display P3.

**Bugs and risks found by the review:**
- RAW highlight headroom is probably clipped.
- Video legal/full range isn't handled.
- Apple Log 2 isn't supported.
- JPEG/HEIC highlights posterize and saturated colors shift after the inversion.
- Integer grain seeds give identical grain.
- Preview/export grain differs by up to about ±27%.
- Halation follows luminance rather than red-layer exposure.
- Wide-gamut video is clipped per channel inside the film model.

---

## 4. Findings

Each finding is laid out as: **What we learned** → **Evidence** → **What we'll do** → **Effort** → **Confidence**.

### F1 · Kodak publishes the data a realistic film model needs
- **What we learned.** Kodak's technical datasheets for its cinema camera film (Vision3 250D, 5207/7207) and its cinema print film (Vision 2383/3383) include:
  - characteristic curves per color layer
  - spectral sensitivity curves (which wavelengths each layer responds to)
  - spectral dye-density curves (what color each dye actually is)
  - sharpness (MTF) and grain (RMS granularity) curves
- **Evidence.**
  - Vision3 250D technical data, Kodak publication H-1-5207 (March 2022).
  - Vision 2383 technical data, Kodak publication H-1-2383 (March 2022).
  - Both are public PDFs from kodak.com.
- **What we'll do.** Digitize these curves (manual chart tracing, with a documented method and accuracy check) and fit our model to them. Start with Vision3 250D (daylight), 500T (tungsten) and the 2383 print.
- **Effort.** Medium: about 1–2 weeks for the first negative + print, including validation.
- **Confidence.** High that the data exists; medium on digitization accuracy. The embedded charts are low-resolution rasters: the 2383 sensitometry chart is about 64 px per log-exposure unit. On the 250D chart, the camera-stop labels disagree with the log-exposure axis by about 6%. So we digitize against the log axis and report uncertainty in data units.
- **Note.** Kodak's data is factual product information, but product names are trademarks. Legal should review how we name looks before launch; descriptive names like "Daylight negative / Cinema print" are the safe default.

### F2 · A spectral simulation is a candidate quality jump (unproven), and it can be fast
- **What we learned.**
  - Film color comes from how each layer's sensitivity curve (F1) overlaps the spectrum of the scene light. Our current model shortcuts this with a 3×3 mix of red/green/blue.
  - Doing it properly needs a full spectrum for each color. A camera only gives three numbers (RGB), so a **spectral upsampling** method has to reconstruct a plausible spectrum from them.
  - Two well-known published methods:
    - **Jakob & Hanika (2019):** smooth, physically plausible spectra from a compact model; needs a pre-computed table.
    - **Mallett & Yuksel (2019):** any sRGB color is a weighted mix of three fixed spectra; simpler, but the spectra are less realistic, per the authors' own project page. It's also limited to the sRGB gamut, so P3/Rec.2020 inputs would have to be clipped first.
  - A **BSD-licensed reference implementation of Jakob–Hanika (rgb2spec)** exists and may be reused with notice.
  - The open-source simulator formerly called agx-emulsion, now **spektrafilm**, uses this spectral approach with published Kodak and Fujifilm data, plus couplers, grain and halation. Per the review:
    - its code is GPL-3.0;
    - its profiles and LUTs are CC BY-SA 4.0, with a no-resale clause;
    - its author asserts that tools inspired by its methods are derivative works.
    
    We therefore **don't study its code or profiles** and work only from primary literature and Kodak/Fujifilm data. That licensing summary comes from the review; legal should confirm it against the repo's license files.
- **Evidence.** Jakob & Hanika, *Computer Graphics Forum* 38(2), 2019 (EPFL publication page); Mallett & Yuksel, *EGSR* 2019 (DOI 10.2312/sr.20191216); agx-emulsion GPLv3 license as listed on FreshPorts; pixls.us discussion threads by the author.
- **What we'll do.**
  1. Implement Jakob–Hanika spectral upsampling (rgb2spec's BSD code may be reused with notice). It must handle wide-gamut and >1 (HDR) inputs.
  2. Compute layer exposure from spectra × Kodak sensitivity curves.
  3. **Pre-compute the whole negative→print chain into a 3D lookup table** for real-time use. Spatial effects (grain, glow) stay as separate GPU passes.
  4. Keep today's parametric model as the fallback and as a test reference.
  5. Bake the *current* parametric model into a lookup table first, so preview, export and .cube share one fast color path. The spectral model then just swaps the table generator.
  6. The spectral model must beat a simple "direct fit" baseline (camera RGB → film fitted directly to datasheet data) in a blind test on real film references.
- **Effort.** Medium-high: about 3–4 weeks.
- **Confidence.** High on the method; medium on how much better it looks in practice. That must be judged on real photos with colorists.

### F3 · Our print stage is too soft; cinema print film is very contrasty
- **What we learned.** Read from Kodak's 2383 chart:
  - the curves rise from about 0.05 to a maximum density of about 4.1, over roughly 3 units of log exposure;
  - the midscale slope (density 0.5 → 3.5) is about 3.5, and the peak slope about 4.5.

  Our print curve peaks at about 2.6 (parameter 2.2, shape 0.5), with a maximum density of about 3.4. Comparing peak with peak (4.0–4.7 vs about 2.55), 2383 is about 1.6–1.8× steeper. The second review re-measured: midscale 3.25–3.69, peak 4.0–4.7, Dmax 4.10. 2383 is measured in **Status A** (the standard for prints). Its dye chart is normalized for a **xenon-arc** projection lamp; its sensitometry was exposed with tungsten light.
- **Evidence.** H-1-2383, sensitometric curves and spectral dye-density chart ("Normalized dyes to form a visual neutral density of 1.0 for a xenon-arc viewing illuminant"). Values were read from the charts by digitizing at 300 dpi against the axis ticks, so they're approximate. This was independently re-measured by our review agent.
- **Caution (review).** Simulated alone, a 2383 refit raises mid-gray display gamma from about 1.24 to about 1.8–2.0 and contrast from about 1000:1 to about 7000:1: too harsh. The steep print only looks right with a printing-density negative and projector flare.
- **What we'll do.** One end-to-end tone-reproduction refit: printing-density negative + 2383 print + flare + xenon white point. Targets are a mid-gray gamma band (e.g. 1.2–1.5), black level and highlight anchors, judged by colorist A/B.
- **Effort.** Medium (not the "quick win" first assumed). **Confidence.** High on the direction.

### F4 · Halation is a choice, not a constant
- **What we learned.** Halation happens when light passes through the film, reflects off the back of the base, and re-exposes the emulsion from behind. In color negative film the red-sensitive layer is generally the one farthest from the lens, so the glow is red-orange. That's per the halation explainers cited below; Kodak's 250D sheet doesn't include a layer diagram. Kodak's cinema negatives traditionally have a black, carbon **rem-jet** backing that absorbs this light; since 2025 Kodak also offers Vision3 with an Anti-Halation Undercoat (AHU) instead of rem-jet, which still prevents halation (https://www.kodak.com/en/motion/page/ahu-announcement/). The well-known red glow of stocks like CineStill 800T comes from removing that backing. Print film has its own anti-halation dye layer, so halation is a camera-negative trait.
- **Evidence.**
  - H-1-5207: "acetate safety base with rem-jet backing."
  - H-1-2383 film-structure section: an anti-halation dye layer under the emulsion.
  - Analog.cafe and CineD explainers on the reflection mechanism and rem-jet removal. These are secondary sources, but they agree with each other.
- **What we'll do.** A "Backing" style switch:
  - *Cinema (rem-jet):* subtle halation.
  - *Removed:* strong red halation.
  
  Size the glow by base thickness relative to the frame, so it scales with film gauge (8/16/35/65 mm).
- **Effort.** Low. **Confidence.** High.

### F5 · Interimage effects make film colors rich and edges crisp
- **Also required (review).** **Masking couplers** (colored couplers, which create the orange mask) are a separate, first-order mechanism for negative color, and the model doesn't include them yet. Kodak's 250D dye chart is D-min-subtracted. See Hunt, *The Reproduction of Colour*, and Giorgianni & Madden, *Digital Color Management*.
- **What we learned.** Color negative films contain **DIR couplers** (development-inhibitor-releasing couplers). Where one layer develops, they release chemicals that slow development in neighboring layers. Patents describe this as giving higher **color contrast while keeping neutral contrast**, correcting unwanted dye absorptions, and improving sharpness and grain. The effect also works locally, at edges.
- **Evidence.** US patents on DIR couplers, e.g. US 5,981,158 and US 5,965,341 (summarized via patent text). These describe purpose and mechanism, not ready-made formulas.
- **What we'll do.** Model the interimage effect in two parts:
  - an **across-the-image** density coupling between layers, tuned so saturated colors gain separation while grays stay neutral;
  - a **local** edge effect, which also produces the "acutance" (edge crispness) colorists ask for.
  
  Validate on color charts.
- **Effort.** Medium. **Confidence.** Medium: the physics is clear, but the strength has to be tuned by eye and by chart.

### F6 · Sharpness differs by color layer
- **What we learned.** In Kodak's sharpness (MTF) charts, the camera negative's **red** layer loses fine detail first, and on the print the **blue** layer loses it first. Exact numbers are read from charts and approximate.
- **What we'll do.** Apply a very slight per-layer softening in the film simulation, scaled to the frame size. It's subtle but contributes to the "not digital" feel.
- **Effort.** Low. **Confidence.** Medium on visual impact; high that the effect is real.

### F7 · Grain should follow density and color layer
- **What we learned.**
  - Kodak's granularity charts show grain strength changing with density and differing per layer. Vision3's "Dye Layering Technology" is described as reducing shadow grain.
  - **Newson et al. (2017)** published a physically based grain model, grain as randomly placed microscopic disks. It's accurate but slow. Its reference code is GPL-licensed, so we implement it from the paper.
  - A 2023 paper, *Film Grain Rendering and Parameter Estimation* (ACM, DOI 10.1145/3592127), reports a very large speed-up over the Monte-Carlo method in its abstract. **Its method is patented: US 12,705,810 B2** (Northwestern University, granted 11 Aug 2026). Reference only; no use without a freedom-to-operate review.
  - The **AV1 video codec** standardizes a grain model: grain generated from a small autoregressive pattern and scaled by brightness through a piecewise-linear curve. Encoders can strip grain and re-add it at playback, saving bandwidth.
- **Evidence.**
  - Kodak H-1-5207 granularity chart.
  - Newson, Faraj, Galerne & Delon, *IPOL* vol. 7, 2017 (DOI 10.5201/ipol.2017.192).
  - AV1 technical overview (arXiv 2008.06091).
  - Andrey Norkin's AV1 film-grain notes.
  - FFmpeg's AV1 grain parameter documentation.
- **What we'll do.**
  1. Grain v2: generated per color layer, with strength driven by each layer's density.
  2. Use Newson's model offline as the **ground truth**; our fast GPU grain must match its statistics within about 10%.
  3. Video: AV1-style grain export isn't actionable on iOS without an AV1 encoder (unverified). Focus on how grain affects HEVC/ProRes bitrate.
- **Effort.** Medium. **Confidence.** High on the approach.

### F8 · Colorists think in printer points; we should too
- **What we learned.**
  - A **printer point** is a step of 0.025 log exposure, i.e. 1/12 of a stop of printing light; 12 points double the light.
  - A correctly exposed 18% gray card reads **25-25-25** in Kodak's transfer-point convention.
  - Kodak notes that one camera stop is about **7 printer points** ("One t-stop is equal to about 7 printer points or 7 transfer points"). That's consistent with the negative's gentle curve: about 0.6 in printing density; the review digitizes 0.47–0.56 in Status M (0.55 × 0.301 ÷ 0.025 ≈ 6.6 points).
- **Evidence.**
  - Wikipedia, *Printer point*.
  - Kodak, *For the Film Timer*.
  - Kodak telecine patent (US 6,115,062).
  - Lowepost article on printer lights.
- **What we'll do.** Make Warmth/Tint use real printer points in the engine (today 1 slider unit = 2 points). Pro mode shows R/G/B points directly. 25-25-25 is a lab/telecine timing convention, so we first define how engine values map to points, then show 25-25-25 as neutral.
- **Effort.** Low. **Confidence.** High.

### F9 · Negatives and prints are measured differently
- **What we learned.** Negatives are measured in **Status M** density and prints in **Status A**, both defined in ISO 5-3. SMPTE RP 180 defines "printing density," which describes how a negative actually prints more accurately than Status M does.
- **Evidence.** ISO 5-3:2009 (catalog entry); SMPTE RP 180-1999; Kodak datasheets (Status M for 5207, Status A for 2383).
- **Print aim (review).** Kodak's laboratory aim (LAD) prints mid-gray to a visual neutral density of 1.0 (Status A 1.09/1.06/1.03). That's about 0.10–0.11 of paper white. Our engine places mid-gray at 0.17 of white, a deliberate display-adaptation choice that should be documented and validated.
- **What we'll do.** Convert digitized curves into the right measurement frame. In the spectral model this happens naturally: we compute printing exposure from the negative's dye spectra and the print's sensitivities.
- **Effort.** Included in F2. **Confidence.** High.

### F10 · Display output is part of the look
- **What we learned.**
  - The industry's open standard **ACES 2.0** renders to displays in a perception-based color space (JMh, a simplified Hellwig 2022 appearance model), with explicit tone scale, chroma compression and gamut compression. A forum post dates aces-core v2.0.0 to April 2025 (secondhand). OpenColorIO first shipped it in 2.4.0 (September 2024) as a "preview"; 2.4.2 removed the preview label.
  - Cinematographer Steve Yedlin's widely cited demos argue that "display preparation" largely *is* the look.
- **Evidence.** ACES Central documentation (rendering overview, gamut compression by Nick Shaw); OCIO 2.4 release notes; yedlin.net *On Color Science* and *Display Prep Demo*; a pixls.us post citing aces-core v2.0.0.
- **What we'll do.**
  - Add explicit outputs: Rec.709 (gamma 2.4), sRGB, P3, and HDR (PQ/HLG).
  - Our print simulation stays the tone scale. For HDR, extend the print's highlight shoulder toward a brightness target.
  - Borrow ACES 2.0's idea of hue-stable gamut compression; we already use the ACES gamut-compression curve for out-of-gamut colors.
- **Effort.** Medium. **Confidence.** High.

### F11 · Camera inputs are done the right way
- **What we learned.** Each log format has a published formula and color gamut. Our implementation decodes each published 18%-gray code value to 0.18 within 0.02%. Apple Log and ARRI LogC4 are checked by round-trip through their published encoding; HLG uses the BT.2408 38% reference.
  - Apple Log 0.4883
  - S-Log3 420/1023
  - LogC3 0.3910
  - V-Log 0.4233
  - DaVinci Intermediate 0.3360
  - ACEScct 0.4136
- **Evidence.** Manufacturer white papers, cross-checked against the open-source colour-science library; our automated tests.
- **Gaps (review).**
  - No legal/full signal-range handling for video. S-Log3, LogC3 and V-Log expect legal-range code values; getting the range wrong costs about −0.9 to +1.05 stops.
  - Apple Log 2 / Apple Wide Gamut (iPhone 17 Pro) isn't supported.
  - iPhone HLG is a camera-rendered signal, not true scene light.
  - The mid-gray tests are partly circular: they check our formulas against themselves.
- **What we'll do.** Fix range handling and add Apple Log 2 first. Then add RED, Canon, Blackmagic, Fujifilm, DJI, Nikon and Samsung logs, each tested against independent reference values (colour-science-generated tables).
- **Effort.** Low per format. **Confidence.** High.

### F12 · The competitive landscape leaves room for us
| Product | Known strengths (public/user sources) | Gap we can fill |
| --- | --- | --- |
| Filmbox (Video Village) | Film realism per many colorists; 98 stocks; real-time 4K; LUT export; HDR outputs | Desktop plug-in only; complex for non-colorists |
| Dehancer | Control, grain, gate weave, "film breath"; native iPhone/iPad app (2026) | Subscription; RAW/log/HDR support on iOS unconfirmed |
| FilmConvert Nitrate | Price, ease | Seen as less "real film" by some colorists |
| Chromagraph (designed by Steve Yedlin; press credits Rian Johnson) | Curated RAW camera look on iPhone | One look, stills only; curated color/tone/texture controls |

- **Evidence.** Product pages (videovillage.com/filmbox, App Store listing); Gizmodo and No Film School launch coverage of Chromagraph; user forums (Reddit r/cinematography, DVXuser), which are anecdotal; CineD reviews.
- **Correction (review).**
  - **Dehancer iOS** is a native iOS 26 app (iPhone and iPad), rebuilt in May 2026, with film profiles, log profiles and video editing.
  - **spektrafilm** ships free in darktable, vkdt and a Resolve OFX plugin.
  - Filmbox pricing: Looks $199, Pro $999 perpetual. It supports ACES 2.0 and RCM and has an "Aura" control.
- **Our position (hypothesis to validate).** "Native mobile + RAW + log + HDR" is **not unique**. We have to win on look quality, ease and workflow. An on-device teardown (Dehancer iOS, Chromagraph, Kino, Blackmagic Camera) and interviews must define a differentiation a user notices in 10 seconds.
- **Confidence.** Medium: forum opinions aren't market research. We should validate with 5–10 colorist interviews.

### F13 · Licensing and IP guardrails
- **spektrafilm (formerly agx-emulsion):** GPL-3.0 code; CC BY-SA 4.0 profiles with a no-resale clause; the author asserts methods-inspired works are derivative. **We don't study its code or profiles**, and legal confirms the terms.
- **Grain patent:** US 12,705,810 B2 covers the 2023 fast grain method. A freedom-to-operate review covers grain, halation and film emulation generally.
- Papers we can implement ourselves: Newson (grain; its IPOL reference code is GPL, so clean-room only), Jakob–Hanika and Mallett–Yuksel (spectral), ACES (published under ACES licensing). Each reference implementation's license must be checked before reuse.
- **Kodak/Fujifilm** data: we use published product data. Product names are trademarks, so legal review is needed before marketing named stocks.
- **Competitors** (Filmbox, Dehancer, Chromagraph): reference for *what* users value only. No copying of looks, data, UI or branding.

---

## 5. Recommended plan

| Order | Work | Why | Size | Success measure |
| --- | --- | --- | --- | --- |
| 0 | Input correctness: RAW headroom, signal range, Apple Log 2, JPEG inversion, grain seeds | Wrong inputs make every look wrong | M | See the review's acceptance criteria (HAM issues) |
| 1 | End-to-end tone refit: printing-density negative + 2383 + flare (F3) + printer points (F8) | Visible quality gain without harshness | M | Mid-gray gamma band agreed; highlight/black anchors; colorist A/B ≥ 3/5 prefer it |
| 2 | Digitize Vision3 250D/500T + 2383 data (F1) | Unlocks everything below | M | Traced curves overlay the charts within 1 px; method documented |
| 3 | Real-material validation (moved up, Codex review) | Synthetic tests can't judge beauty; must come before more stocks | M | 30-image / 10-clip set + real film test (HAM-89); 5 colorists rate vs Filmbox/Dehancer |
| 4 | Display outputs incl. HDR (F10), rendered from film state before the SDR clip | Required by colorists and for video | M | Standard reference values per output |
| 5 | Spectral negative→print model baked to 3D LUT (F2, F9), only if it beats a fitted RGB baseline on real data | Candidate realism jump | M-L | Beats RGB baseline on paired film/digital data; GPU vs reference within 0.5 step |
| 6 | iPhone performance (live preview, 4K video) | "Fast and fluid" promise | M | 120 Hz preview, 4K30 playback, < 1 GB memory |
| 7 | Grain v2 (F7), interimage + acutance (F5), per-layer sharpness (F6), halation switch (F4) | The organic details | M | Statistical tests vs references; colorist review |
| 8 | Video pipeline + LUT export | Product scope | L | Exports verified; LUT matches engine within 1 step |

---

## 6. Risks and open questions

- **Real-world look quality is unproven.** All tests are synthetic. *Mitigation:* plan step 5 early, with colorists.
- **Chart digitization error** could bias color. *Mitigation:* overlay checks, multiple stocks, and fitting by eye + chart.
- **iPhone performance** of a 3D LUT plus spatial passes at 4K60 is unmeasured. *Mitigation:* device benchmark harness first.
- **Trademarks** in stock names. *Mitigation:* legal review; descriptive names.
- **Scope.** RAW + video + log + Pro is a lot. *Mitigation:* the shared engine; ship the easy app first.

---

## 7. Glossary

- **Scene light / scene-referred:** a numeric description of the light in the scene (0.18 = a mid-gray card), before any "look."
- **Log footage:** video stored with a logarithmic curve so it holds a wide brightness range; it looks flat until graded.
- **Characteristic (H&D) curve:** how much dye density a film makes for each amount of light.
- **Density:** how much light a film area blocks, on a log scale (density 1 = 10% of light passes, 2 = 1%).
- **Stop:** a doubling or halving of light.
- **Printer point:** 1/12 of a stop of printing light (0.025 log exposure); how labs and colorists balance color.
- **Status M / Status A:** standard ways to measure density for negatives (M) and prints (A).
- **Spectral sensitivity:** how strongly a film layer responds to each wavelength of light.
- **Spectral upsampling:** reconstructing a plausible light spectrum from three RGB numbers.
- **3D LUT:** a pre-computed color lookup table; very fast to apply.
- **Halation:** red-orange glow around bright lights caused by light reflecting inside the film.
- **Rem-jet:** the black backing on cinema negatives that prevents halation.
- **Interimage effect / DIR couplers:** chemistry where one color layer's development restrains the others, increasing color separation and edge crispness.
- **MTF:** a measure of sharpness at different detail sizes.
- **Gamut:** the range of colors a device or format can show (e.g., Display P3, Rec.709).
- **HDR (PQ/HLG):** high-dynamic-range video standards for brighter displays.

---

## 8. Sources

**Kodak (primary)**
- KODAK VISION3 250D 5207/7207 technical data, H-1-5207, March 2022: https://www.kodak.com/content/products-brochures/Film/VISION3-250D-Technical-Data-EN.pdf
- KODAK VISION Color Print Film 2383/3383 technical data, H-1-2383, March 2022: https://www.kodak.com/content/products-brochures/Film/KODAK-VISION-Color-Print-Film-2383-3383-data-sheet.pdf
- Kodak, *For the Film Timer*: https://kodak.com/en/motion/page/for-the-film-timer

**Papers**
- Jakob & Hanika 2019, spectral upsampling: https://rgl.epfl.ch/publications/Jakob2019Spectral
- Mallett & Yuksel 2019, spectral primary decomposition: https://diglib.eg.org/items/bbffa865-e99c-4c1f-bd33-70102dc8af78/full · project page https://graphics.geometrian.com/research/spectral-primaries.html
- Newson, Faraj, Galerne & Delon 2017, realistic film grain rendering: https://www.ipol.im/pub/art/2017/192
- *Film Grain Rendering and Parameter Estimation*, ACM 2023 (DOI 10.1145/3592127): https://doi.org/10.1145/3592127

**Standards and video**
- AV1 technical overview: https://arxiv.org/pdf/2008.06091
- Andrey Norkin, AV1 film grain: https://norkin.org/research/film_grain/
- ACES 2.0 output transforms:
  - https://docs.acescentral.com/system-components/output-transforms/technical-details/rendering-overview/
  - gamut compression: https://draftdocs.acescentral.com/output-transforms/technical-details/gamut-compression
- OpenColorIO 2.4 release notes: https://opencolorio.readthedocs.io/en/main/releases/ocio_2_4.html
- SMPTE RP 180: https://pub.smpte.org/pub/rp180/rp0180-1999_stable2006.pdf
- ISO 5-3:2009 catalog entry: https://iteh.es/catalog/standards/iso/6cdfb60e-5093-43ae-b7a4-7102bd9170bd/iso-5-3-2009

**Film practice**
- Printer point: https://en.wikipedia.org/wiki/Printer_point
- Kodak telecine patent US 6,115,062: https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/6115062
- Lowepost, printer lights: https://wwwa.lowepost.com/insider/insights/printer-lights-r33
- Halation explainers:
  - https://www.analog.cafe/r/halation-in-film-photography-i3q4
  - https://www.cined.com/chasing-the-glow-understanding-halation-and-why-filmmakers-keep-coming-back-to-it/
- DIR coupler patents:
  - https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/5981158
  - https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/5965341
- Steve Yedlin:
  - https://www.yedlin.net/NerdyFilmTechStuff/OnColorScience/
  - https://www.yedlin.net/DisplayPrepDemo/index.html

**Open source and products**
- spektrafilm (formerly agx-emulsion), as reported by the review: https://github.com/andreavolpato/spektrafilm · FreshPorts (old name): https://www.freshports.org/graphics/py-agx-emulsion/ · darktable module: https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/spektrafilm/ · discussion https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209
- Dehancer iOS rebuild (May 2026): https://blog.dehancer.com/2026/05/04/this-isnt-an-update-its-a-new-app/
- rgb2spec (BSD, Jakob–Hanika reference): https://github.com/mitsuba-renderer/rgb2spec
- Grain patent US 12,705,810 B2: https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12705810
- colour-science (log curves cross-check): https://colour.readthedocs.io/
- Filmbox: https://videovillage.com/filmbox/
- Chromagraph Camera (App Store): https://apps.apple.com/us/app/chromagraph-camera/id6803329435
- Chromagraph launch coverage: https://gizmodo.com/the-last-jedi-director-launches-a-new-camera-app-for-iphone-because-hes-a-good-guy-2000832061 · https://nofilmschool.com/rian-johnson-steve-yedlin-app
- Forum comparisons (anecdotal):
  - https://reddit.rtrace.io/r/cinematography/comments/1ctmmeb/does_anyone_use_film_emulation_tools_for_your
  - https://www.dvxuser.com/threads/film-emulation-plugins.5708159/

---

## 9. Review log

An independent review agent re-read every claim against the sources and the code, without editing.

**Corrected after review:**
- the print-contrast numbers (F3)
- the neutral-gray range (§3)
- the precision wording for the log curves (F11)
- the 16-stop wording (§2)
- the performance caveats
- JPEG vs HEIC bit depth
- the Newson author order and GPL note
- the 2023 grain-paper citation
- the halation layer-order source
- the OCIO version (2.4.2)
- the printer-point target definition
- the Chromagraph credits
- the market-position claim, now marked as a hypothesis

**Confirmed by the review:**
- the Kodak publication numbers and quotes
- Status M (negative) vs Status A (print)
- the rem-jet backing
- the per-layer sharpness findings
- the printer-point arithmetic
- the papers' venues
- agx-emulsion's GPLv3 license
- all 20 engine tests passing

### Second review (deep adversarial), 28 Oct 2026

The full report is in `docs/REVIEW-2026-10-28.md`. Verdict: **adjust strongly, and rethink positioning**. The engine math and log constants were verified, and the Kodak readings were re-measured and confirmed.

**New findings (now reflected above):**
- **Market:** Dehancer iOS and free spektrafilm undercut the original market claim.
- **Inputs:** RAW highlight clipping is likely; video range handling and Apple Log 2 are missing; the JPEG inversion posterizes highlights.
- **Grain:** integer seeds give identical grain.
- **Tone:** a naive 2383 refit over-contrasts.
- **Legal:** the 2023 grain method is patented, and spektrafilm's license terms are stricter than first reported.
- **Performance:** targets are unproven on iPhone.

I independently checked the most critical claims:
- Apple's `CIRAWFilter.h` says `extendedDynamicRangeAmount` 0 "indicates no extended dynamic range output";
- the seed bug follows directly from `fract(p·k + seed)` with integer seeds;
- the Dehancer May 2026 blog post is confirmed;
- the darktable spektrafilm module docs are confirmed.
