# Film theory for the Emulsion engine

**What this is.** The physics and measurement conventions that the E2 "film realism" work implements, with equations and primary sources, and a map of what the engine does today against each of them. It answers MOV-18 (literature notes: DIR/interimage, Status M vs A vs printing density, projection flare) and MOV-19 (primary-literature review of couplers and masking).

**Date:** 7 November 2026 · **Engine reviewed:** `main` at `0ea0473` (film-model constants unchanged since `c9fd154`) (`FilmModel.swift`, `Emulsion.ci.metal`, `Renderer.swift`, `FilmLook.swift`) · **Data inventory:** `docs/STOCK-DATA.md` (MOV-15).

**Rules followed.**
- Primary sources only: Kodak and Fujifilm publications, ISO/SMPTE documents, patents, and the standard textbooks. No spektrafilm/agx-emulsion code, profiles or documentation was opened (GPL / CC BY-SA, see MOV-19).
- Every claim carries a source tag. **[Verified]** means the source was opened in this session and the statement checked against it. **[Book]** means a standard textbook or journal paper that was *not* opened in this session: the content is textbook-level, but chapter/page numbers are not checked. **[Derived]** means our own derivation from the cited equations; the steps are shown. **[Unverified]** means we could not check it and it must not be relied on until someone does.
- Engine behavior is labeled **Modeled** (a physical mechanism with a physical parameter), **Approximated** (the right mechanism, simplified or with fitted rather than measured parameters) or **Artistic** (a look choice with no physical claim).

Plain-language glossary for terms used below:
- **Density** $D$: how much light a film area blocks, on a log scale. $D = -\log_{10} T$, where $T$ is transmittance (fraction of light passing). $D = 1$ passes 10%, $D = 2$ passes 1%.
- **Log exposure** $\log_{10} H$: published characteristic curves use photometric exposure (illuminance × time, lux·s). A spectral model instead computes weighted layer exposures, which need calibration to that published scale; film responds roughly to their logarithms.
- **Gamma** $\gamma$: the slope $dD/d\log_{10}H$ of the characteristic curve.
- **Spectral product / responsivity**: the wavelength-by-wavelength product of a light source, filters and a detector; it defines what a "density" measures.

---

## 1. Sensitometry: H&D curves

### 1.1 The characteristic curve
A film's response is described by its characteristic (H&D, after Hurter and Driffield) curve: density against log exposure, per color record.

$$
D_i = F_i(\log_{10} H_i), \qquad H_i = \int E(\lambda)\, t\, s_i(\lambda)\, d\lambda \quad (i = R, G, B)
$$

- $E(\lambda)$ is spectral irradiance at the film, $t$ the exposure time, $s_i(\lambda)$ the spectral sensitivity of layer $i$. The integral gives an effective layer exposure: sensitivity normalization and a per-layer exposure offset must calibrate it to the lux·s scale of the published $F_i$ curves under their stated illuminant. It is not automatically a photometric lux·s integral. **[Derived: model calibration requirement]**
- Kodak plots $F_i$ against "LOG EXPOSURE (lux-seconds)" (2383; the 500T chart's top axis) or against log exposure plus a "Camera Stops" axis (250D). **[Verified: H-1-2383, H-1-5207, H-1-5219 chart axes]** Digitize against the log axis. On the 250D chart the camera-stop tick marks agree with it (0.300 log E per stop, stop 0 at −1.30 log lux·s); only the printed stop labels are unevenly placed, which is what the earlier "about 6%" figure (review E10) measured. On the 500T chart the log-axis ticks are unevenly drawn (up to about 0.06 log E off a straight line) and the stop ticks imply 0.3125 log E per stop, about 4% more than $\log_{10} 2$; the chart does not say which axis is right. **[Verified: tick positions measured on the chart images, MOV-16; `StockData/*/manifest.json`]**
- Reciprocity: within a stated range of exposure times the curve depends only on $H$, not on how it splits between intensity and time. VISION3 250D needs no correction "from 1/1000 of a second to 1 second"; 2383 shows "little or no change in tone scale" from 1/10 s to about 1/3000 s. **[Verified: H-1-5207 Mar 2022 p.2; H-1-2383 Mar 2022 p.3]**
- Hurter & Driffield, *J. Soc. Chem. Ind.* 9 (1890). **[Book]**

**Gamma** is the slope of the straight-line portion, $\gamma_i = dD_i/d\log_{10}H_i$. Camera negatives have low gamma (wide latitude); print films have high gamma. Digitized values used in this project (300 dpi chart reads, approximate; method in `docs/REVIEW-2026-10-28.md` §3 E9–E10):

| Curve | Densitometry | Straight-line / midscale slope | Source |
| --- | --- | --- | --- |
| VISION3 250D (R, G, B) | Status M | 0.47–0.48, 0.55–0.56, 0.54–0.55 | review E10 **[Verified by the review, not re-measured here]** |
| VISION 2383 (B, G, R), D 0.5→3.5 | Status A | 3.46, 3.25, 3.69 (peak 4.0–4.7), Dmax 4.10 | review E9 **[Verified by the review, not re-measured here]** |

An independent check on the print slope near the aim point: Kodak's LAD sheet says that near aim, "changing one printer light of TRIM (0.025 Log Exposure Unit) will result in approximately 0.07 density change on the print". **[Verified: H-61b]** That implies a local print gamma near mid-gray of

$$
\gamma_{\text{print, LAD}} \approx 0.07 / 0.025 = 2.8. \quad \textbf{[Derived]}
$$

### 1.2 Densities add (spectrally)
The three dye layers sit in series, so their spectral densities add (Beer–Lambert, transmittances multiply):

$$
D(\lambda) = D_{\text{base+fog}}(\lambda) + \sum_k c_k\, \varepsilon_k(\lambda)
$$

$c_k$ is the amount of dye $k$ and $\varepsilon_k(\lambda)$ its unit spectral density. **[Book: Hunt, *The Reproduction of Colour*, 6th ed., Wiley 2004, chapters on subtractive colour and densitometry]**

**Important consequence:** this additivity holds *per wavelength*. Integral densities (Status A, Status M, printing density, §2) are logs of *integrals* over a band, so they are only approximately additive. Any model that does its bookkeeping in three integral densities (as the engine does now) carries this approximation. **[Derived]**

### 1.3 What the datasheet curves actually are
Getting the frame right matters more than digitizing precisely:

- **Negative characteristic curves are Status M.** 250D: "Exposure: 5500 K Daylight, 1/50 sec; Process: ECN-2; Densitometry: Status M". **[Verified: H-1-5207 chart label, 2022 and Mar 2026 sheets carry the same chart image]** The 500T characteristic chart is labeled "Densitometry: ECN-2" in both the Jul 2015 and Mar 2026 sheets (a mislabel); only its MTF and spectral-sensitivity charts say Status M. **[Verified: H-1-5219t 2015 p.4; H-1-5219 Mar 2026 p.3]** Status M for the 500T curves is an inference. **[Unverified]**
- **Print characteristic curves are Status A**, exposed through a tungsten source with "KODAK Heat Absorbing Glass, No. 2043 (plus Series 1700 Filter)", 1/500 s. **[Verified: H-1-2383 chart label]**
- **Spectral sensitivity curves are defined at a density criterion**: "Sensitivity = reciprocal of exposure (erg/cm²) required to produce specified density"; 250D uses "Density: 0.2>D-min" (Status M), 2383 uses "D = 1.0". **[Verified: chart labels]** Using them as linear weights $s_i(\lambda)$ assumes the curve shape does not change with density. That is a standard approximation, not something the sheets state. **[Derived]**
- **Negative spectral dye curves are "D-mins subtracted" and peak-normalized**, and the chart also plots "Midscale Neutral" and "Minimum Density" spectra. **[Verified: H-1-5207 p.4 chart]** The minimum-density curve contains base, fog and the unused masking couplers (§3.3), so it is the starting point for reconstructing the orange mask. Only the three dye curves are D-min-subtracted: the digitized Midscale Neutral matches a scaled sum of the dyes within 0.035 D (250D) and 0.017 D (500T) once Minimum Density is subtracted from it, and misses by 0.18–0.20 D otherwise. The magenta curve is slightly negative near 445 nm, as expected where a yellow-colored coupler is consumed (§3.3). **[Verified on the digitized curves (local reference data, not in the repo; `docs/STOCK-DATA.md`): `DyeSumCheck` in `EmulsionFit`, MOV-17; tracing error in `StockData/README.md`]**
- **The minimum-density spectrum reproduces the characteristic chart's toe in Status M.** Integrated through ISO 5-3:1995 Status M, the digitized Minimum Density spectrum gives R/G/B 0.210/0.548/0.848 for 250D against the chart's lowest traced densities 0.175/0.577/0.844 (differences +0.035/−0.028/+0.004 D), and 0.164/0.553/0.832 against 0.189/0.584/0.841 for 500T. At 10 nm within 400–700 nm the midscale neutral − Dmin is matched by dye amounts C/M/Y 0.574/0.627/0.656 (250D, max residual 0.027 D at 570 nm) and 0.741/0.700/0.778 (500T, 0.016 D at 510 nm; 500T's minimum density is traced only from 425 nm). **[Computed from digitized datasheet spectra: `emulsion-fit dyes`, MOV-88; not a measurement of film]** This supports reading the 500T characteristic chart as Status M too, without proving it. **[Derived]**
- **Print spectral dye curves** are "Normalized dyes to form a visual neutral density of 1.0 for a xenon-arc viewing illuminant". The page text calls them peak-normalized, but the Aug 2026 chart plots peaks of about 0.81 (yellow), 0.88 (magenta) and 1.09 (cyan). **[Verified: H-1-2383 p.5 chart; digitized, MOV-17]** Over 400–700 nm the Visual Neutral sits a roughly constant 0.075 D above the plain sum of the three curves and rises steeply below 400 nm; the chart does not say what that extra density is. **[Verified on the digitized curves; cause Unverified]**

---

## 2. Measuring density: Status M, Status A and printing density

All of these are the same formula with a different spectral weighting $\Pi_c(\lambda)$:

$$
D_c = -\log_{10} \frac{\int \Pi_c(\lambda)\, T(\lambda)\, d\lambda}{\int \Pi_c(\lambda)\, d\lambda}
$$

$\Pi_c$ is the **spectral product** (source × optics × filter × detector) for channel $c$. **[Verified: ST 2065-2:2020 Eq. 1 and definitions 3.4, 3.7; ISO 5-3:2009 Introduction 0.2–0.3]**

### 2.1 Status A and Status M (ISO 5-3)
- ISO 5-3:2009 defines both as tabulated spectral products: "ISO 5 standard status A density" (clause 6.3) and "status M density" (clause 6.4), plus a clause 6.2 "ISO 5 standard printing density". Transmittance densities use CIE illuminant A (≈2856 K) modified by a heat-absorbing filter. **[Verified: ISO 5-3:2009 public preview, contents and §0.4]** The 2009 tables are paywalled; its Annex A was **not** read. **[Unverified: any change between the 1995 and 2009 tables]**
- The **Status M** table was read from the 1995 edition: ISO 5-3:1995 Table 4 ("Status M — log10 spectral products", normalized to 5.000 at the peak, 10 nm, with log slopes for extrapolation beyond each channel's span), via the public copy of ANSI/ISO 5-3-1995, ANSI/NAPM IT2.18-1996 p. 8: https://law.resource.org/pub/us/cfr/ibr/001/aimm.it2.18.1996.pdf. Peaks: **B 450 nm, G 540 nm, R 640 nm**. **[Verified: IT2.18-1996 p. 8; transcribed locally, provenance and SHA-256 in `EmulsionFit/Resources/standards-manifest.json`]** Status A tables were not read. **[Unverified]**
- Purpose: Status A is for materials viewed directly (prints, transparencies); Status M is for materials meant to be printed (negatives). **[Book: Hunt; consistent with Kodak's use of Status M for 5207 and Status A for 2383]**
- ISO 5-3 itself explains why there are several: for viewing, the response should simulate illuminant × eye; for printing, "the spectral power distribution of the source to be used in the printing operation and the spectral sensitivity of the print material need to be simulated". **[Verified: ISO 5-3:2009 §0.2]**

### 2.2 Printing density (SMPTE RP 180)
Status M only approximates how a negative prints. RP 180 says so directly: "status M densities can only approximate printing densities for most materials", and defines printing density as "the density of the negative as 'seen' by the printer and print material". **[Verified: RP 180-1999 Introduction]**

- **Responsivities.** Table 1 tabulates R, G, B responses at 10 nm, normalized to 1 at their peaks: **B peaks at 430 nm, G at 530 nm, R at 670 nm.** **[Verified: RP 180-1999 Table 1]**
- **Equations.** RP 180 §3 defines $E_c = \int c_\lambda\, TF_\lambda\, d\lambda \,/\, \int c_\lambda\, TS_\lambda\, d\lambda$ ($TF$ film transmittance, $TS$ reference transmittance, e.g. Dmin or clear) and then prints $PD_c = \text{LOG}_{10}(E_c)$. **[Verified: RP 180-1999 p.3]** As printed this has the wrong sign (it gives negative densities for a film darker than the reference); the density convention, and ST 2065-2 Eq. 1, use $PD_c = -\log_{10} E_c$. Treat the RP 180 sign as a typo. **[Derived; ST 2065-2 Verified]**
- **Status M → printing density.** RP 180 suggests computed printing densities "can be used to derive a transformation matrix to transform status M density measurements to printing density". **[Verified: RP 180-1999 §3]** That is exactly what we need for datasheet curves: a 3×3 matrix (per stock, fitted from its dye spectra) from Status M to printing density.
- RP 180-1999 is marked "ARCHIVED DECEMBER 12, 2006" on the public copy. **[Verified]** Its modern successor for interchange is APD (§2.3).

### 2.3 Academy Printing Density and ADX (SMPTE ST 2065-2 / 2065-3)
- **APD** (ST 2065-2:2020) defines printing density with responsivities $\Pi_{\text{APD}}$ "based on the spectral sensitivities of contemporary motion picture print films such as those of the Kodak Vision family, of the Fujifilm Eterna family, and of Fujifilm F-CP", a Bell & Howell Model C printer lamp house with dichroic filters, and a Wratten 2B filter. Responsivities are tabulated at 2 nm in the accompanying `st2065-2a-2020.csv`. Measurement geometry is ISO 5-2 diffuse transmission. **[Verified: ST 2065-2:2020 Introduction, §4.1]**

$$
\text{APD}_c = -\log_{10}\left(\frac{1}{\Pi_{\text{sum},c}} \sum_\lambda \Pi_{\lambda,c}\, T_\lambda\right) \qquad \textbf{[Verified: ST 2065-2 Eq. 1]}
$$

- **ADX** (ST 2065-3:2020) stores Dmin-subtracted APD as integers:

$$
\begin{aligned}
\text{ADX16}_c &= \max\!\big(0, \min(65535, \operatorname{round}(k_c (\text{APD}_c - \text{APD}_{c,\text{Dmin}}) \cdot 8000 + 1520))\big)\\
\text{ADX10}_c &= \max\!\big(0, \min(1023, \operatorname{round}(k_c (\text{APD}_c - \text{APD}_{c,\text{Dmin}}) \cdot 500 + 95))\big)
\end{aligned}
\qquad k_R = 1.00,\ k_G = 0.92,\ k_B = 0.95
$$

**[Verified: ST 2065-3:2020 Eqs. 1–2]** The per-channel $k_c$ scale green and blue down relative to red. **[Derived; the standard does not explain the choice of factors]** The offset (1520 / 95) gives footroom for densities below the assumed Dmin. **[Verified: §4.3.2 NOTE]**

ST 2065-2 NOTE 3 says Status M → APD conversion is product-specific and may use a 3×3 matrix plus offset, a polynomial or a 3D LUT. A matrix must therefore be validated rather than assumed exact. **[Verified: ST 2065-2 NOTE 3, p.7]**

**Why it matters for Emulsion:** printing density is the natural internal variable between our negative and print stages (§4), and ADX is how scanned negatives arrive in a colorist's world. An ADX input (scan → our print stage) and an APD-referred negative stage would make the engine interoperable with ACES film workflows (see gap G-12).

### 2.4 Visual density and the print aim
- **Kodak LAD** (Laboratory Aim Density): the LAD patch "is printed to a neutral gray of 1.0 visual density". On 2383/3383 and 2393/3393, "the Status A density aim is 1.09 red, 1.06 green, and 1.03 blue". **[Verified: H-61b; the same aim as a table in H-1-2393 (1998); H-1-5207 states only the 1.0 visual density]**
- **Fujifilm** aims a normally exposed 18% gray card to Status A R 1.10, G 1.05, B 1.05 on ETERNA-CP 3513DI (and on F-CP), "based on the assumption that the film will be projected with a xenon lamp projector". **[Verified: Fujifilm Motion Picture Film Manual KB-0707E, pp. 47, 51]**
- Taking the LAD aim of 1.0 as total visual density, mid-gray transmits $10^{-1.0} = 0.10$ of open-gate luminance. Relative to a clear print with visual Dmin about 0.05 (review E9), it transmits $10^{-(1.0-0.05)} \approx 0.11$. Open gate means no film; it is a different reference from clear print. **[Derived; Dmin is an approximate chart read]**

---

## 3. The color negative

### 3.1 Structure and spectral sensitivities
- A color negative has three emulsion records: blue-sensitive forming yellow dye, green-sensitive forming magenta, red-sensitive forming cyan. In camera negatives the blue record is conventionally on top (nearest the lens) with a yellow filter layer below it, and the red record nearest the base. **[Book: Hunt; James (ed.), *The Theory of the Photographic Process*, 4th ed., 1977]** Kodak's VISION3 sheets do **not** show a layer diagram, and Kodak's "Dye Layering Technology" may imply more than three sub-layers. **[Derived/Unverified: the sheets only say DLT reduces shadow grain]** **[Unverified: the exact VISION3 layer order]**
- Print film is ordered differently: on 2383 "The bottom layer is sensitive to blue light and produces the yellow dye image… The next layer is sensitized to red light and yields the cyan dye image… The top image-forming layer is sensitized to green light and produces magenta dye." **[Verified: H-1-2383 Film Structure]**
- Layer exposure is $H_i = \int E(\lambda)\, t\, s_i(\lambda)\, d\lambda$ (§1.1). The 250D sensitivity curves overlap noticeably (e.g. green and red between about 560–620 nm; chart read, approximate). **[Verified visually: H-1-5207 p.4]**

### 3.2 Dye formation
In chromogenic development, oxidized developer couples with a coupler in each layer to form dye in proportion to developed silver; the silver is then bleached and fixed out (ECN-2 for negatives, ECP-2E for prints). **[Book: Hunt; James]** **[Verified: process names, H-1-5207 and H-1-2383]** The characteristic curve $F_i$ measures integral density through the densitometer's spectral product, not dye concentration directly. A spectral model must infer dye amounts from those measurements and the dye spectra, including base and masking couplers (§1.2, §3.3). **[Derived]**

### 3.3 Masking couplers (the orange mask)
Real dyes absorb outside their intended band ("unwanted absorptions"): magenta absorbs some blue, cyan absorbs some green and blue. Printing would then turn those into color errors. Colored (masking) couplers correct this:

- In the green record, the coupler itself is **yellow** (it absorbs blue). Where magenta dye forms, coupler is consumed, so its yellow absorption disappears in proportion to the magenta formed. **[Book: Hanson & Vittum, "Colored dye-forming couplers in subtractive color photography", *J. Photogr. Soc. Am.* 13 (1947); Hunt; Giorgianni & Madden, *Digital Color Management*, 2nd ed., Wiley 2008]**
- Kodak's DIR patent describes reducing "yellow-colored magenta dye-forming masking couplers" to lower blue minimum density. **[Verified: US 5,981,158, detailed description]**

Spectral model for the green record's contribution at wavelength $\lambda$ in the blue band, with $m$ the magenta dye amount, $m_{\max}$ the coupler supply, $\varepsilon_m(\lambda)$ magenta's spectral density per unit dye and $\varepsilon_c(\lambda)$ the colored coupler's spectral density per unit coupler:

$$
D^{(\text{green record})}(\lambda) = \varepsilon_m(\lambda)\, m + \varepsilon_c(\lambda)\,(m_{\max} - m)
\;\;\Rightarrow\;\;
\frac{\partial D(\lambda)}{\partial m} = \varepsilon_m(\lambda) - \varepsilon_c(\lambda)
$$

With $\varepsilon_c(\lambda) = \varepsilon_m(\lambda)$ across the blue band, that spectral density no longer depends on how much magenta formed: the unwanted absorption has become a constant spectrum, $\varepsilon_m(\lambda)\, m_{\max}$, which shows up as extra Dmin (part of the orange cast) and is removed by the printer lights. Where $\varepsilon_c(\lambda) > \varepsilon_m(\lambda)$, the mask over-corrects the unwanted absorption, which can raise color separation. Equality of fitted broadband coefficients alone does not establish spectral cancellation. The cyan record uses a reddish coupler (absorbing green and blue light, adding magenta and yellow density) the same way for its unwanted green and blue absorptions. **[Derived from the mechanism in the sources above]**

**On the Kodak sheets the mask is already inside the dye curves.** The negative dye curves are drawn "D-mins subtracted" (§1.3), so each is $\varepsilon_k - \varepsilon_{c,k}$, the net change per unit dye formed with its coupler consumed, and the Minimum Density curve holds the unconsumed couplers. The reconstruction $D(\lambda) = D_{\min}(\lambda) + \sum_k c_k\,\varepsilon_k^{\text{net}}(\lambda)$ therefore needs no separate coupler spectra. Through APD, the resulting printing density per unit dye (250D, fitted over the neutral scale and a lattice of dye amounts) is approximately R ← 0.919 C + 0.079 M − 0.002 Y, G ← 0.112 C + 0.851 M + 0.094 Y, B ← 0.053 C + 0.073 M + 0.850 Y (PD ≈ P·c + b with the neutral scale weighted 10, the engine's form; the offset b is under 0.004 D): the remaining cross-terms are small and positive, i.e. the masking leaves little net unwanted absorption in printing density. **[Computed from digitized datasheet spectra: `emulsion-fit dyes`, MOV-88; the hold-end assumption outside traced spans moves these entries by up to about 0.02]**

In integral-density terms this is a **negative-side 3×3 correction applied to dye amounts before printing**, with off-diagonal terms that can cancel (or overcancel) the dyes' cross-absorptions. The dye-and-coupler bookkeeping is linear in spectral density, but the subsequent spectral integral and logarithm are nonlinear. A 3×3 mapping in integral printing density is a fitted approximation, even when the density frame is correct (§1.2, §2.2). **[Derived]**

### 3.4 DIR couplers and interimage effects
**Mechanism.** Development-inhibitor-releasing (DIR) couplers form dye and release an inhibitor where a layer develops. The inhibitor restrains development in the same layer and in neighboring layers. Kodak's patents state the effects directly: DIR couplers "release inhibitors that can restrain silver development in the layer in which release occurs"; they can "control gamma or contrast", "enhance sharpness or acutance", "reduce granularity" and provide "color correction via interlayer interimage effects". **[Verified: US 5,965,341 and US 5,981,158 background]**

- **Interlayer (color) interimage:** inhibitor from a "causer" layer lowers development in a "receiver" layer. Exposing red therefore *lowers* green and blue density where red light fell, beyond what neutral exposures show: more color separation without changing the neutral scale (if the film is designed for it). Interimage effects as a measurable color-reproduction mechanism: Hanson & Horton, "Subtractive color reproduction: interimage effects", *JOSA* 42 (1952). **[Book]** DIR couplers: Barr, Thirtle & Vittum, *Photogr. Sci. Eng.* 13 (1969). **[Book]**
- **Patent metric:** US 5,965,341 measures interimage as the ratio of receiver gamma to causer gamma, $G_r/G_g$ (red-record gamma over green-record gamma, from exposures in its test films), with a no-inhibitor reference of $1.10/1.27 = 0.87$; a DIR coupler counts as effective when the ratio falls below that. **[Verified: US 5,965,341, examples]** US 5,981,158 uses blue as causer and green as receiver. **[Verified]** Neither patent gives a general equation for interimage.
- **Fujifilm** describes its new Super-Efficient DIR-Coupler Technology for ETERNA 250 as giving "further enhancements in color and sharpness"; the earlier phrase about improved definition and color reproduction refers to existing DIR couplers. **[Verified: ETERNA 250 product information, 2005]**

**Model we will implement (engineering form, not from a source).** Inhibition reduces development in proportion to the density formed in other layers. Let $e$ be a neutral log-exposure coordinate, and let $F_j(e)$ be record $j$'s fitted neutral characteristic curve at that coordinate. For a uniform neutral input, choose $e$ to be its common layer log exposure. The color residual is $q_j = D_j - F_j(e)$:

$$
D_i' = D_i - \sum_{j \neq i} k_{ij}\,q_j, \qquad q_j = D_j - F_j(e)
$$

- For a uniform neutral exposure $D_j = F_j(e)$, every $q_j$ is zero, so each record's neutral scale is untouched even when the R/G/B curves differ; the datasheet's neutral curves already *include* the film's real interimage, so we fit $F_i$ to them and add only the color-dependent part. **[Derived]**
- Positive cross-channel inhibition can increase record separation; for equal curves and a shared coefficient $k$, zero-mean color residuals are multiplied by $1+k$. With unequal curves or coefficients, this is not a guarantee of increased saturation. The coordinate $e$, coefficients and saturation behavior must be fitted and tested; this is a candidate local approximation, not an established film law. **[Derived]**
- **Local (edge) interimage** uses the same equation with $q_j$ replaced by a blurred $h * q_j$ (inhibitor diffuses tens of micrometres; see §6.3). **[Unverified: diffusion distance for VISION3]**
- The strengths $k_{ij}$ are not published. They must be fitted to real-film references (MOV-89) or tuned on charts and labeled **Approximated**.

---

## 4. Printing

### 4.1 Print exposure from the negative
The print film sees the negative through the printer. Per print layer $i$:

$$
H^{\text{print}}_i = K_i \int S_{\text{printer}}(\lambda)\, F_{\text{filters}}(\lambda)\, s^{\text{print}}_i(\lambda)\, T_{\text{neg}}(\lambda)\, d\lambda
$$

If the printing-density responsivities match the printer × print film product (that is what RP 180 and APD aim for), this collapses to

$$
\log_{10} H^{\text{print}}_i = \log_{10} H^{0}_i - PD_i \qquad \textbf{[Derived from RP 180 §§1–3 and ST 2065-2 Introduction]}
$$

so the negative's printing density simply subtracts from the printer's log exposure, channel by channel. That is exactly the engine's current form (`logP = printerLights + lights − dNeg`), **provided `dNeg` is printing density**. Today it is a generic density with no defined frame (gap G-1).

### 4.2 Printer lights and points
- Additive printers set R, G, B light with "printer points" (lights). One point is **0.025 log exposure**: "changing one printer light of TRIM (0.025 Log Exposure Unit)". **[Verified: H-61b]** So 12 points ≈ 0.30 log E ≈ one stop of printing light. **[Derived]**
- Kodak's rule of thumb: "One t-stop is equal to about 7 printer points or 7 transfer points". **[Verified by the earlier review: kodak.com "For the Film Timer"; not re-opened here]** At 7 points per stop, a stop of camera exposure moves printing density by $7 \times 0.025 = 0.175$, i.e. a negative printing-density gamma of $0.175 / 0.301 \approx 0.58$. **[Derived]** That sits above the Status M straight-line gammas (0.47–0.56), consistent with printing density differing from Status M (§2.2).
- Printer timing: $\log_{10} H^0_i = c_i + 0.025\, P_i$, where $P_i$ are the printer lights. Lab timing chooses $P_i$ so the LAD patch prints to its Status A aim (§2.4). Lights run on a 50-step scale with a mid value used as reference; the "25-25-25" neutral is a lab/telecine convention, not a physical constant. **[Verified by the earlier review: "For the Film Timer"; Unverified: any universal printer-light origin]**
- Fujifilm documents an example Bell & Howell Model C setup for ETERNA-CP: 1000 W lamp, SC41 + heat-absorbing filter 2043, trimmer 13-13-13, tape 25-25-25, ND R 0.50 / G 0.55 / B 0.90. **[Verified: KB-0707E p.51]**

### 4.3 The print stock
- Print dye amounts are fitted functions $c^{\text{print}}_i = G^{\text{print}}_i(\log_{10} H^{\text{print}}_i)$, chosen so the resulting Status A measurements reproduce the published H&D curves $F_i$. A measured integral density $F_i$ cannot be substituted directly for dye amount, and base density must be counted once. **[Derived: spectral reconstruction requirement]** The print's spectral transmittance is $T_p(\lambda) = 10^{-(D_{\min,p}(\lambda) + \sum_i c^{\text{print}}_i \varepsilon^{\text{print}}_i(\lambda))}$. **[Book: Hunt; §1.2]**
- **2383** is the reference: Status A curves, Dmax ≈ 4.1, midscale slope ≈ 3.3–3.7 (§1.1); polyester ESTAR base 120 µm; antihalation layer of "proprietary solid particle dyes… coated under the emulsion"; no rem-jet. **[Verified: H-1-2383 Mar 2022; the Aug 2026 revision keeps the same text and charts, with the dye-density chart redrawn at higher resolution]**
- **2393 (VISION Premier)**: "The upper tone scale… is significantly higher in density than EASTMAN EXR Color Print Film… The toe areas of the sensitometric curves are matched more closely, producing more neutral highlights"; same LAD Status A aim as 2383; with the same soundtrack negative its print density "is about .1 higher than 2383". **[Verified: H-1-2393, Sept 1998 (cinematography.net copy)]** No current Kodak-hosted 2393 sheet was found (see `STOCK-DATA.md`).
- **Fujifilm ETERNA-CP 3513DI**: characteristic curves in Status A, exposed at 2854 K 1/100 s through SC-41, CC-90Y and CC-60M; **"Curves G and B are shifted 1.0 Log H to avoid overlapping"**. **[Verified: KB-0707E p.53]** Anyone digitizing it must undo that shift; the manual gives the same shift for F-CP (p.47) and 3521XD (p.55). The manual states no gamma. The frequently quoted "ASC: 3513 gamma 2.6" is **not used** here: it was never traced to a primary source (MOV-15).

### 4.4 Lab variations (for MOV-35)
- Push/pull and "skip-bleach" processing "may require more extreme adjustment from the LAD printing condition" (Mar 2022 sheet); the Mar 2026 sheet says instead "Testing is recommended with specialized negative processing techniques (push, pull, 'skip-bleach', etc.)". **[Verified: H-1-5207 LAD section, both revisions]**
- Their sensitometric effect (gamma, Dmin, retained silver adding a neutral density) is not tabulated in the sheets. **[Unverified: magnitudes; needs a lab source or the MOV-89 test]**

---

## 5. Projection and viewing

### 5.1 Light source
- SMPTE ST 196:2003: for 35 and 70 mm prints, screen light should approximate "a blackbody at a color temperature of 5400 K + 600 K – 200 K, the use of short-arc xenon light sources being assumed", with a typical reading of "D5500: x = 0.332 and y = 0.347". **[Verified: ST 196:2003 §7.1]**
- Kodak normalizes 2383's dyes "for a xenon-arc viewing illuminant". **[Verified: H-1-2383 chart]**

### 5.2 Luminance and flare
- Theater screen luminance is nominally **55 cd/m² (16 fL)** open gate at screen center, allowed 41–75 cd/m²; review rooms 55 ± 7 cd/m². **[Verified: ST 196:2003 §§5.2–5.4]**
- **Stray light:** "Screen luminance due to stray light shall be less than 0.16% (600:1 theater screen contrast ratio) for review rooms and primary theaters. For all other theaters… less than 0.25% (400:1…)". **[Verified: ST 196:2003 §10.2]**

Screen luminance with flare, as a fraction $f$ of open-gate luminance $L_0$:

$$
L = L_0 \left(10^{-D_{\text{vis}}} + f\right), \qquad 0 \le f < 0.0016 \text{ (review room)}
$$

**[Derived from ST 196 §10.2; the additive-veil form is the standard flare model, Book: Hunt]** Here $D_{\text{vis}}$ is total visual density; subtracting Dmin would instead normalize transmission to a clear print. If a print reaches total visual density 4 ($10^{-4} = 0.0001$), flare near the 0.0016 ceiling can be about 16× larger than its own black transmission. **When flare dominates, it sets the projected black and lifts the shadow tone scale.** Kodak's ≈4.1 Dmax is a Status A chart reading, so using it as visual density is only an estimate. ST 196 provides an upper bound on stray light, not a required flare floor. **[Derived]**

### 5.3 Surround and system gamma
- Film is viewed in a dark surround. A dark surround lowers perceived contrast, so projected images need a higher end-to-end gamma than images viewed in an average surround; Hunt gives about 1.5 for dark, 1.25 for dim and 1.0 for average surrounds. **[Book: Hunt, tone reproduction chapter; Bartleson & Breneman, "Brightness perception in complex fields", *JOSA* 57 (1967)]** **[Unverified: exact figures and page]**
- Emulsion renders for phone and monitor viewing (dim-to-average surround), not a dark theater. A physically correct theater print therefore *should* be adapted for the display (gap G-7). Today that adaptation is implicit in the engine's choice of mid-gray (§7).

---

## 6. Image structure: halation, grain, sharpness

### 6.1 Halation and anti-halation layers
- **Mechanism.** Light that passes through the emulsion into the base can reflect at the base/air (or base/backing) interface and re-expose the emulsion from behind, spreading a glow around bright points. Light hitting the back surface beyond the critical angle $\theta_c = \arcsin(1/n)$ is totally internally reflected; for a base of index $n \approx 1.5$, $\theta_c \approx 42°$, so the reflected light lands in a ring of radius about $r \approx 2t\tan\theta$ for base thickness $t$. **[Book: James; geometry Derived]** **[Unverified: the refractive index and thickness of VISION3 acetate base; the sheets do not state them]**
- **Color.** The layer nearest the base (red-sensitive in a conventional negative, §3.1) receives the reflected light first, and the blue and green parts are largely absorbed on the way down, so halation on color negative is red/orange. **[Book: James, Hunt]** **[Unverified for VISION3: layer order not published]**
- **Rem-jet → AHU.** The Mar 2022 VISION3 sheets: "acetate safety base with rem-jet backing". **[Verified: H-1-5207 2022]** The **Mar 2026** sheets for 50D, 250D, 200T and 500T: "An Anti-halation undercoat replaces the traditional remjet backing layer", base "acetate safety base". **[Verified: H-1-5203/5207/5213/5219, Revised 3-26]** Kodak's AHU page calls it "a new VISION3 Camera Negative Film structure – without remjet backing… an Anti-Halation Undercoat layer". **[Verified: kodak.com/en/motion/page/ahu-announcement]** The sheets make no quantitative halation claim for either design. **[Unverified: AHU vs rem-jet halation strength]**
- **The 2026 sheets reuse the 2022 charts byte for byte** (MTF, granularity, sensitometry, spectral sensitivity, dye density) for 250D and 50D. **[Verified: SHA-256 of extracted chart images]** So either the AHU change does not alter the published curves, or the curves were not re-measured. We cannot tell which. **[Unverified]**
- **Print film** has its own antihalation layer "coated under the emulsion" plus absorber dyes that reduce intragrain light scatter, "further reducing halation". **[Verified: H-1-2383]** Treating print halation as negligible is an engineering assumption, not a measured bound. **[Unverified: magnitude]**
- **No backing (e.g. rem-jet removed by the user or a reseller):** strong red halation. This is widely observed but we have no primary measurement. **[Unverified: magnitude]**

**What a physical model needs** (for MOV-32): halation added to the *red-layer exposure* (not luminance), from light that has passed the emulsion (so weighted by the scene's red-band exposure and the emulsion's transmittance), spread by a ring/disk kernel whose radius scales with base thickness relative to the frame, with strength set by the backing (none / AHU / rem-jet). **[Derived]**

### 6.2 Grain
- **Measurement.** Kodak plots "Diffuse rms Granularity" as $\sigma_D$ against log exposure, "Read with a microdensitometer, using a 48-micrometre aperture"; "multiply by 1000 for the rms value". **[Verified: H-1-5207, H-1-5219; the 2383 and 2393 sheets state no aperture]** The granularity chart is plotted with the characteristic curve so $\sigma_D$ can be read at any density. **[Verified: chart instructions]**
- **Aperture scaling (Selwyn's law).** For apertures much larger than the grain, $\sigma_D \sqrt{A}$ is constant:

$$
\sigma_D(A) = \sigma_D(A_0)\sqrt{A_0/A} \qquad \textbf{[Book: Selwyn, *Photogr. J.* 75 (1935); Dainty \& Shaw, *Image Science*, 1974]}
$$

  For a square pixel of side $p$ on the film versus Kodak's 48 µm circular aperture ($A_0 = \pi \cdot 24^2\ \mu\text{m}^2$): $\sigma_{\text{pixel}} = \sigma_{48}\cdot \sqrt{\pi}\cdot 24/p \approx 42.5\,\sigma_{48}/p$ (p in µm). **[Derived]** Example: a frame about 24.9 mm wide at 4096 px gives $p \approx 6.1$ µm, so $\sigma_{\text{pixel}} \approx 7\,\sigma_{48}$. Selwyn's law is only approximate when $p$ approaches the dye-cloud size (a few µm). **[Unverified: dye-cloud size for VISION3]**
- **Density dependence.** For randomly placed opaque grains of mean area $a$ (Nutting's model, $D = 0.434\, N a$), Poisson statistics give

$$
\sigma_D^2 = \frac{0.434\, a\, D}{A} \qquad \textbf{[Derived from Nutting, *Phil. Mag.* 26 (1913), Book; Dainty \& Shaw]}
$$

  so silver granularity grows like $\sqrt{D}$. Dye clouds are not opaque discs and DIR couplers and layering change the curve, which is why Kodak's measured curves (which rise, flatten and differ per layer) should drive the model rather than the formula. **[Derived]**
- **Grain is in density.** A density fluctuation $\delta D$ multiplies transmittance by $10^{-\delta D}$; small fluctuations give $\delta T / T \approx -\ln 10\, \delta D$. Negative grain is printed through the print's gamma, so on screen it scales by about the print gamma; the print adds its own (smaller) granularity. **[Derived]**

### 6.3 Sharpness: MTF and adjacency
- Kodak publishes MTF ("Response %" vs cycles/mm) per layer: 250D at 5500 K Status M; 2383 at 3200 K Status A with a "35% Modulation Target". **[Verified: chart labels]** The negative's red record falls off first; on the print, blue falls off first. **[Verified by the earlier review]**
- **Cascading:** $M_{\text{system}}(f) = \prod_k M_k(f)$ for linear stages (camera lens, negative, printer, print, projector lens). **[Book: Dainty & Shaw]** Film is not linear in exposure, so this holds only for small modulations. **[Book]**
- **Gaussian fit:** if a layer's MTF is modeled as $M(f) = e^{-2\pi^2\sigma^2 f^2}$, its 50% frequency $f_{50}$ gives $\sigma = \sqrt{\ln 2 / (2\pi^2)}/f_{50} \approx 0.187/f_{50}$ (σ in mm if $f$ in cycles/mm). **[Derived]**
- **Adjacency (edge) effects.** Developer exhaustion and inhibitor diffusion near edges make dense areas denser at their borders and thin areas thinner, so measured MTF can exceed 100% at low frequencies (Kodak's MTF axes run to 200%). **[Book: James; Dainty & Shaw]** A linearized model:

$$
D'(x) = D(x) + a\,\big(D(x) - (h * D)(x)\big)
$$

  with $h$ a normalized kernel the width of the chemical spread. **[Book: form after Nelson, *Photogr. Sci. Eng.* 15 (1971); Unverified: citation details]** This is an unsharp mask *in density*, which is what MOV-33 should implement, not in display RGB.

---

## 7. How the engine maps onto this

Measured with a Python mirror of `FilmModel.swift` (calibrated printer lights; neutral input; measured below +1.5 stops, where highlight chroma retention is inactive). The probe is archived outside git at `~/Documents/Emulsion Research/Film science 2026-11-07/engine_probe.py`; numbers reproduce from the constants in `Packages/EmulsionCore/Sources/EmulsionCore/FilmModel.swift`. It measures the color chain without spatial effects (halation, local tone or grain).

| Quantity | Engine today | Reference | Source |
| --- | --- | --- | --- |
| Negative slope at mid-gray | 0.58 / 0.60 / 0.63 (R/G/B) | 0.47–0.56 Status M; ≈0.58 printing density from the 7-points rule | §1.1, §4.2 |
| Print slope at the mid-gray operating point | 2.12 / 2.07 / 1.98 | ≈2.8 near LAD (H-61b); 3.3–3.7 midscale | §1.1 |
| Print peak slope | 2.43–2.61 | 4.0–4.7 | §1.1 |
| Mid-gray print density above paper | 0.77 (output 0.17 of white) | ≈0.95 above clear-print Dmin (≈0.11 of clear print; 0.10 of open gate) | §2.4 |
| System gamma at mid-gray (display/scene, log-log) | 1.24 | ≈1.5 for dark-surround projection | §5.3 |
| Black / paper-white contrast | ≈1000:1 | ≈600:1 at the review-room stray-light ceiling; higher contrast possible below it | §5.2 |

Stage-by-stage:

| Stage | Code | Status | Notes |
| --- | --- | --- | --- |
| Layer exposure | `sensitivity` 3×3 on linear Display P3 (`FilmModel.swift:19`, kernel `filmRender`) | **Approximated** | A fitted basis change with small negative terms. Not derived from Kodak's spectral sensitivities. Saturated light can go negative and is clamped. Real version: spectra × $s_i(\lambda)$ (MOV-22, MOV-23). |
| Negative H&D | `negativeDensity`: logistic, gamma 0.60–0.65, range 3.0 | **Approximated** | Right mechanism. Shape and parameters are generic, not fitted to a stock, and the density frame (Status M vs printing density) is undefined (G-1). |
| Negative dyes, mask, unwanted absorptions | none: negative density goes straight to print exposure | **Missing** | No masking couplers, no negative cross-absorption, no printing-density conversion (G-2, MOV-88). |
| Interimage / DIR | none (the comment on `sensitivity` says so) | **Missing** | G-3, MOV-27. |
| Printing | `logP = printerLights + lights − dNeg` | **Modeled** (form) | Correct form *if* `dNeg` is printing density (§4.1). |
| Printer lights | calibrated so 18% gray prints neutral at 0.17; user lights in log10 | **Modeled** | `FilmLook.printerPoint = 0.05` per control unit = 2 printer points (0.025 log E each, §4.2). |
| Print H&D | Richards curve, gamma 2.05–2.20, range 3.3, shape 0.5 | **Approximated** | Softer than 2383 (table above); deliberately, because there is no flare or printing-density negative yet (G-5, MOV-5). |
| Print dyes | `printDyes` 3×3 on integral densities | **Approximated** | Integral-density crosstalk instead of spectral dyes × xenon × observer (§1.2; MOV-26, MOV-17). |
| Viewing | $10^{-(D-D_{\text{paper}})}$, white = paper white = display white; D65 P3 output | **Approximated** | No xenon illuminant or chromatic adaptation, no flare, no surround (G-6, G-7). |
| Mid-gray placement | `middleGrayOut = 0.17` | **Artistic** (display adaptation) | LAD would be ≈0.11. Brighter mid-gray partly compensates for the missing dark-surround/flare context. Should be documented as a display-prep choice and validated (G-7). |
| Highlight chroma retention | blend toward ratio-preserving render above +1.5 stops (`FilmModel.swift:53`, kernel `filmSystem`) | **Artistic** | No photochemical counterpart. Colors never reach white and timing is partly undone (MOV-99). Expected to shrink or go once masking/interimage and a spectral print exist. |
| Halation | luminance threshold 2.0 (≈+3.5 stops), tint (1, 0.32, 0.10), core + skirt blur (`Renderer.swift:37`, kernel `halationSource`) | **Artistic** | Mechanism is real, but driven by luminance not red-layer exposure, tint and radii are not measured, and no backing type (G-8, MOV-32, MOV-102, MOV-31). |
| Grain | value noise on cube-root lightness, midtone envelope (kernel `grain`) | **Artistic** | Not in density, not per layer, not driven by Kodak $\sigma_D$ curves or Selwyn scaling (G-9, MOV-30). |
| Sharpness / adjacency | none | **Missing** | G-10, G-11 (MOV-34, MOV-33). |

---

## 8. Gap list

Ordered roughly by impact on the look. Each gap names the E2 issue that owns it.

| ID | Gap | Physics section | Issue |
| --- | --- | --- | --- |
| G-1 | Define the negative's density frame: fit negative curves in Status M from the sheets, then fit a per-stock conversion to printing density (APD) from dye spectra; test whether 3×3 plus offset is sufficient (RP 180 §3; ST 2065-2 NOTE 3). **Computed (MOV-88, digitized datasheet spectra):** for 250D a colour-fitted Status M → APD 3×3 (fitted over the neutral scale and a 9×9×9 dye-amount lattice) leaves up to about 0.02 D (green) on the neutral scale (0.004/0.020/0.005 D, R/G/B) and about 0.095 D at the extreme corners of the dye lattice (lattice RMS 0.004/0.018/0.005, max 0.018/0.095/0.023 D). An offset lowers the neutral-scale figure to about 0.013 D (green) and leaves the lattice within 0.002 D of the same. A 3×3 fitted to neutrals alone reaches 0.003 D on neutrals but misses colours by up to about 0.84 D, so it is useless for colours. For 500T the colour-fitted figures, with and without offset, are within 0.005 D of these. The engine's matrix is from dye amounts instead, PD ≈ P·c + b with the neutral scale weighted 10: neutral scale within 0.004/0.006/0.002 D, lattice RMS 0.006/0.024/0.012 D (max 0.025/0.125/0.047 D); the printer lights absorb b. The largest misses are green at strongly colored corners; whether that matters for images is open. APD straight-line gammas (250D) 0.506/0.578/0.524 against Status M 0.476/0.558/0.538. | §1.3, §2.2–2.3, §4.1 | MOV-25, MOV-88 |
| G-2 | Negative dye set: unwanted absorptions + masking couplers, reconstructed from the "Minimum Density" and "Midscale Neutral" spectra on H-1-5207. **Computed (MOV-88):** the net dye curves plus Minimum Density reproduce the midscale neutral within 0.027 D (250D) and 0.016 D (500T) at 10 nm, 400–700 nm, and the chart's lowest Status M densities within 0.035 D; printing density per unit dye (the engine's P matrix, residuals in G-1) in §3.3. Open: the hold-end assumption below the dyes' traced spans moves APD by up to 0.1 D and RP 180 blue by up to 0.6 D at high density. | §3.3 | MOV-88, MOV-17 |
| G-3 | Interimage: neutral-preserving density coupling (§3.4 equation) plus a local edge term; fit $k_{ij}$ to real film. | §3.4 | MOV-27 |
| G-4 | Spectral layer exposure from scene spectra × Kodak spectral sensitivities (note the density criterion they are defined at). | §1.1, §1.3, §3.1 | MOV-22, MOV-23, MOV-16 |
| G-5 | Tone refit together: printing-density negative + 2383 print (≈2.8 slope near LAD, 3.3–3.7 midscale) + flare. Fitting the print alone over-contrasts. | §1.1, §4, §5.2 | MOV-5 |
| G-6 | Spectral print + projection: print dyes (xenon-normalized) × xenon 5400 K SPD × observer, flare $0 \le f < 0.0016$, adaptation to the display white. | §4.3, §5.1–5.2 | MOV-26, MOV-17 |
| G-7 | Display adaptation: decide and document how a dark-surround theater print maps to a phone/monitor (system gamma, mid-gray 0.17 vs LAD 0.11). | §5.3, §7 | MOV-5 (decision), MOV-9 (output transforms) |
| G-8 | Halation v2: red-layer exposure source, base-thickness-scaled kernel, backing switch (none / AHU / rem-jet), exposure-order fix. | §6.1 | MOV-32, MOV-102, MOV-31 |
| G-9 | Grain v2: per-layer density noise from Kodak negative $\sigma_D$ curves at 48 µm (print measurement apertures unresolved), Selwyn-scaled to pixel size and gauge; through the print. | §6.2 | MOV-30, MOV-31 |
| G-10 | Per-layer MTF from Kodak curves (negative and print), applied in exposure/density at the right stage. | §6.3 | MOV-34 |
| G-11 | Adjacency effect as an unsharp mask in density. | §6.3 | MOV-33 |
| G-12 | ADX/APD interoperability: accept ADX16/ADX10 scans as negatives and expose the negative stage in APD. | §2.3 | **No issue yet (proposed)** |
| G-13 | Lab controls with physical meaning: push/pull, print density (points), bleach bypass (retained silver). Magnitudes need a source. | §4.4 | MOV-35 |
| G-14 | Highlight chroma retention: re-evaluate once G-2/G-3/G-6 land; keep only as a labeled artistic control if still needed. | §7 | MOV-99 |
| G-15 | Ground truth for everything above: 250D/500T test, ECN-2, scan (ADX), optionally a 2383 print measured in Status A. | all | MOV-89 |

**Open questions nobody has answered from a primary source yet:** VISION3 layer order and base thickness/index; AHU vs rem-jet halation strength; DIR strengths; Status A spectral tables and the ISO 5-3:2009 Status M table (paywalled; the 1995 Status M table is read, §2.1); whether the 2026 AHU sheets' unchanged curves were re-measured.

---

## Sources

**Opened and checked in this session** (archive and SHA-256 in `docs/STOCK-DATA.md`):
- SMPTE RP 180-1999, *Spectral Conditions Defining Printing Density in Motion-Picture Negative and Intermediate Films* (archived 2006): https://pub.smpte.org/pub/rp180/rp0180-1999_stable2006.pdf
- SMPTE ST 2065-2:2020, *Academy Printing Density (APD) — Spectral Responsivities, Reference Measurement Device and Spectral Calculation*: https://pub.smpte.org/latest/st2065-2/
- SMPTE ST 2065-3:2020, *Academy Density Exchange Encoding (ADX) — Encoding Academy Printing Density (APD) Values*: https://pub.smpte.org/latest/st2065-3/
- SMPTE ST 196:2003, *Motion-Picture Film — Indoor Theater and Review Room Projection — Screen Luminance and Viewing Conditions*: https://pub.smpte.org/latest/st196/
- ISO 5-3:2009, *Density measurements — Part 3: Spectral conditions* (public preview only): https://standards.iteh.ai/catalog/standards/iso/6cdfb60e-5093-43ae-b7a4-7102bd9170bd/iso-5-3-2009
- Kodak H-1-5207 (VISION3 250D), Mar 2022 and Mar 2026; H-1-5203 (50D), H-1-5213 (200T), H-1-5219 (500T), Mar 2026; H-1-5219t (500T), Jul 2015; H-1-2383 (VISION 2383), Mar 2022 and Aug 2026; H-1-2393 (VISION Premier 2393), Sept 1998; H-61b (LAD for VISION Color Print Film). URLs in `STOCK-DATA.md`.
- Kodak, *AHU announcement*: https://www.kodak.com/en/motion/page/ahu-announcement/
- Fujifilm, *Motion Picture Film Manual*, Ref. No. KB-0707E (c. 2007); Fujifilm, *ETERNA 250 product information* (2005). URLs in `STOCK-DATA.md`.
- US 5,965,341 (Kodak, 1999), *Photographic element containing particular coupler combination*: https://patents.google.com/patent/US5965341A/en
- US 5,981,158 (Kodak, 1999), *Photographic element containing a DIR coupler*: https://patents.google.com/patent/US5981158A/en

**Cited from the literature, not opened in this session** (content is standard; chapter/page not checked):
- R. W. G. Hunt, *The Reproduction of Colour*, 6th ed., Wiley, 2004.
- E. J. Giorgianni & T. E. Madden, *Digital Color Management: Encoding Solutions*, 2nd ed., Wiley, 2008.
- T. H. James (ed.), *The Theory of the Photographic Process*, 4th ed., Macmillan, 1977.
- J. C. Dainty & R. Shaw, *Image Science*, Academic Press, 1974.
- F. Hurter & V. C. Driffield, *J. Soc. Chem. Ind.* 9 (1890).
- W. T. Hanson Jr. & P. W. Vittum, "Colored dye-forming couplers in subtractive color photography", *J. Photogr. Soc. Am.* 13 (1947).
- W. T. Hanson Jr. & C. A. Horton, "Subtractive color reproduction: interimage effects", *JOSA* 42 (1952).
- C. R. Barr, J. R. Thirtle & P. W. Vittum, "Development-inhibitor-releasing (DIR) couplers in color photography", *Photogr. Sci. Eng.* 13 (1969).
- C. J. Bartleson & E. J. Breneman, "Brightness perception in complex fields", *JOSA* 57 (1967).
- E. W. H. Selwyn, "A theory of graininess", *Photogr. J.* 75 (1935).
- P. G. Nutting, *Phil. Mag.* 26 (1913).
- C. N. Nelson, adjacency-effect model, *Photogr. Sci. Eng.* 15 (1971).

**Deliberately not used:** spektrafilm / agx-emulsion (GPL-3.0 code, CC BY-SA 4.0 profiles; MOV-19); the unsourced "ASC: Fuji 3513 gamma 2.6" quote (MOV-15).
