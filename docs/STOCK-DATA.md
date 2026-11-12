# Stock data inventory

**What this is.** Every public technical document found for the cinema stocks the stock library could use (MOV-15): where it is, which revision, which curves it contains and in which densitometry, and the license and trademark position. The theory these curves feed is in `docs/FILM-THEORY.md`.

**Date:** 7 November 2026. Every URL below was downloaded on this date; "Verified" means the file was opened and the row checked against it.

## How to read the table
- **Char** = characteristic (H&D) curves; **SS** = spectral sensitivity; **Dye** = spectral dye density; **MTF** = modulation transfer; **Gran** = diffuse RMS granularity. **Y** = present, **N** = absent, **?** = not checked.
- **Densitometry** is what the characteristic curves are measured in. It decides how the curves are used (`FILM-THEORY.md` §1.3, §2).
- Kodak negative granularity is "Read with a microdensitometer, using a 48-micrometre aperture" (×1000 for the rms value); the 2383/2393 sheets state no aperture. Kodak spectral sensitivity is "reciprocal of exposure (erg/cm²) required to produce specified density"; the density criterion is listed where read.

## Kodak camera negatives (ECN-2)

| Stock | Document | Revision | Char | SS | Dye | MTF | Gran | Densitometry and conditions | URL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VISION3 50D 5203/7203 | H-1-5203 | **Mar 2026** (AHU) | Y | Y | Y | Y | Y | Status M (assumed; chart images identical to Mar 2022) | https://www.kodak.com/content/products-brochures/motion-picture/KODAK-VISION3-50D-5203-7203-technical-information.pdf |
| VISION3 50D 5203/7203 | H-1-5203 | Mar 2022 (rem-jet) | Y | Y | Y | Y | Y | as above | https://www.kodak.com/content/products-brochures/Film/VISION3_50D_5203_TI-2657_Technical-Data_EN.pdf |
| VISION3 200T 5213/7213 | H-1-5213 | **Mar 2026** (AHU) | Y | Y | Y | Y | Y | ? (chart labels not read) | https://www.kodak.com/content/products-brochures/motion-picture/KODAK-VISION3-200T-5213-7213-technical-information.pdf |
| VISION3 250D 5207/7207 | H-1-5207 | **Mar 2026** (AHU) | Y | Y | Y | Y | Y | Status M; 5500 K daylight 1/50 s; SS at D = 0.2 above Dmin; dye curves "ECN-2; D-mins subtracted", peak-normalized, plus Midscale Neutral and Minimum Density spectra | https://www.kodak.com/content/products-brochures/motion-picture/KODAK-VISION3-250D-5207-7207-technical-information.pdf |
| VISION3 250D 5207/7207 | H-1-5207 | Mar 2022 (rem-jet) | Y | Y | Y | Y | Y | as above (identical chart images) | https://www.kodak.com/content/products-brochures/Film/VISION3-250D-Technical-Data-EN.pdf |
| VISION3 500T 5219/7219 | H-1-5219 | **Mar 2026** (AHU) | Y | Y | Y | Y | Y | 3200 K tungsten 1/50 s; chart says "Densitometry: ECN-2" (mislabel, same as 2015); MTF and SS charts Status M; Status M for the curves is inferred, unverified | https://www.kodak.com/content/products-brochures/motion-picture/KODAK-VISION3-5219-7219-technical-information.pdf |
| VISION3 500T 5219/7219 | H-1-5219t | Jul 2015 (rem-jet) | Y | Y | Y | Y | Y | chart also says "Densitometry: ECN-2"; dye curves "D-mins subtracted", Midscale Neutral | https://www.kodak.com/content/products-brochures/Film/VISION3-500T-Color-Negative-Film-7219-TECHNICAL-DATA.pdf |

**Findings.**
- **Kodak replaced rem-jet with an Anti-Halation Undercoat (AHU) on all four VISION3 negatives in the Mar 2026 sheets:** "An Anti-halation undercoat replaces the traditional remjet backing layer." Kodak's announcement: https://www.kodak.com/en/motion/page/ahu-announcement/ (also lists a "Product Change Notice", not downloaded).
- **Film structure and the AHU (MOV-32).** Kodak, *Processing KODAK Motion Picture Films*, Module 7A, Process ECN-2B, ©2026, "Film Structure": overcoat, UV, blue, yellow filter, green, interlayer, red, AHU layer, subbing layer, support, anti-static layer. https://www.kodak.com/content/pdfs/motion/Processing-KODAK-Motion-Picture-Films-Module-7A.pdf, SHA-256 050dda1126be8c8bcaae2d0809e1a7a84ed54fde94a0a36bd1b1daf82a84a3c9. Kodak, "VISION3 AHU Camera Negative Films — Talking points for Filmmakers", May 2025: the AHU is a silver-containing gel layer whose density is removed in processing and which "performs equally" to rem-jet; no halation measurement. Kodak's document, hosted by a reseller: https://www.freestylephoto.com/static/pdf/product_pdf/kodak/Kodak_AHU_FilmMaker_Talking_points.pdf, SHA-256 0d8e9aa6904f977a53745a4a3c2979f72035f973b697ea46f3d3a1f5c47d3e27.
- **The 2026 charts are the 2022 charts.** For 250D and 50D every embedded chart image is byte-identical between the two revisions (SHA-256 of the images extracted with `pdfimages`). 200T and 500T were not compared. So the published curves do not show any effect of the AHU change, and we cannot tell whether they were re-measured.
- The embedded charts are low-resolution rasters (e.g. 250D sensitometry 664×688 px, 250D chart images 213–257 ppi; 2383 sensitometry 490×496 px at 150 ppi). Digitizing accuracy is limited to roughly 0.05–0.1 density (review F-6).

## Kodak print films (ECP-2)

| Stock | Document | Revision | Char | SS | Dye | MTF | Gran | Densitometry and conditions | URL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VISION 2383/3383 | H-1-2383 | **Aug 2026** | Y | Y | Y | Y | Y | Status A; 1/500 s tungsten + Heat Absorbing Glass No. 2043 + Series 1700 filter; chart says "ECP-2D" while the text says ECP-2E; SS at D = 1.0; dye curves "Normalized dyes to form a visual neutral density of 1.0 for a xenon-arc viewing illuminant", peak-normalized, with a Visual Neutral spectrum. The dye chart is redrawn at 577×593 px (was 401×390), the best source for MOV-17. | https://www.kodak.com/content/products-brochures/motion-picture/KODAK-VISION-Color-Print-Film-2383-3383-technical-information.pdf |
| VISION 2383/3383 | H-1-2383 | Mar 2022 | Y | Y | Y | Y | Y | as above | https://www.kodak.com/content/products-brochures/Film/KODAK-VISION-Color-Print-Film-2383-3383-data-sheet.pdf |
| VISION Premier 2393/3393 | H-1-2393 | Sept 1998 | Y | Y | N | Y | Y | curves unlabeled; LAD aim in Status A: 1.09/1.06/1.03; ECP-2B; "print density… about .1 higher than 2383" for soundtracks. Third-party copy. | https://www.cinematography.net/Files/VISPREM.PDF |
| LAD for VISION print films | H-61b | © 1992 (PDF 2001) | Y (typical 2383 and 2393 curves, E.N.D.) | N | N | N | N | LAD patch = 1.0 visual density; Status A aim 1.09 R / 1.06 G / 1.03 B on 2383 and 2393; one printer light (0.025 log E) ≈ 0.07 print density near aim | https://www.kodak.com/content/products-brochures/Film/LAD-for-KODAK-VISION-Color-Print-Film-H-61b.pdf |

No Kodak-hosted 2393 data sheet was found. Kodak's 2393 product page and resources page did not list one on 7 Nov 2026.

## Kodak other stocks

| Stock | Document | Revision | Char | SS | Dye | MTF | Gran | Densitometry and conditions | URL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EKTACHROME 100D 5294/7294 (E-6 reversal) | Sell sheet K-1086.24.05.28.EN.01 | May 2024 | Y | Y | Y | Y | Y | Not read from the charts (raster). A full H-1 technical data sheet was not found (the guessed kodak.com URL returns 404). | https://www.kodak.com/content/products-brochures/Film/EKTACHROME-100D-sell-sheet-EN.pdf |
| EASTMAN DOUBLE-X 5222/7222 (B&W) | H-1-5222 | Mar 2022 | Y | Y | N/A (silver) | Y | Y (single value) | Granularity "Read at a net diffuse visual density of 1.0, using a 48-micrometer aperture"; MTF "Diffuse Visual", developed in D-96; resolving power given | https://www.kodak.com/content/products-brochures/Film/DOUBLEX-Technical-Data-EN.pdf |

## Fujifilm (discontinued; third-party copies only)

Fujifilm ended motion-picture film production around 2013 and no longer hosts these documents (per MOV-15; not re-checked here). The only primary document found is Fujifilm's own manual, mirrored by a third party.

| Stock | Document | Revision | Char | SS | Dye | MTF | Gran | Densitometry and conditions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ETERNA Vivid 160 (8543) | Fujifilm *Motion Picture Film Manual*, Ref. No. KB-0707E | file dated 13 Nov 2007 | Y | N | N | N | N | Status M; 3200 K, 1/50 s, SC-41; x-axis in camera stops |
| ETERNA 250 (8553) | same | same | Y | N | N | N | N | Status M; 3200 K, 1/50 s |
| ETERNA 400 (8583) | same | same | Y | N | N | N | N | Status M; 3200 K, 1/50 s |
| ETERNA 500 (8573) | same | same | Y | N | N | N | N | Status M; 3200 K, 1/50 s |
| F-64D (8522) | same | same | Y | N | N | N | N | Status M; 5400 K, 1/50 s |
| ETERNA 250D (8563) | same | same | Y | N | N | N | N | Status M; 5400 K, 1/50 s |
| REALA 500D (8592) | same | same | Y | N | N | N | N | Status M; 5400 K, 1/50 s |
| F-CP (positive) | same | same | Y | N | N | N | N | Status A; 2854 K, 1/100 s; aim R 1.10 / G 1.05 / B 1.05 for xenon projection; G and B shifted 1.0 log H |
| **ETERNA-CP 3513DI** (positive) | same | same | Y | N | N | N | N | Status A; 2854 K tungsten 1/100 s through SC-41 + CC-90Y + CC-60M; aim R 1.10 / G 1.05 / B 1.05 for xenon projection; **"Curves G and B are shifted 1.0 Log H to avoid overlapping"**; no gamma stated |
| ETERNA-CP 3521XD (positive) | same | same | Y | N | N | N | N | Status A; 2854 K, 1/100 s; G and B shifted 1.0 log H |
| ETERNA 250 (8553) | *ETERNA 250 product information* | PDF dated Sept 2005 | N | N | N | N | N | Text only: EI 250 tungsten / 160 daylight; describes DIR-coupler and grain technologies |

- Manual URL: https://www.theodoropoulos.info/attachments/076_fujifilm_motion_picture_film_manual.pdf (40 pages; also covers ETERNA-CI and ETERNA-RDI intermediates).
- ETERNA 250 product info URL: https://cinematography.net/Files-2/ETERNA250_product_info.pdf
- **Not found:** ETERNA Vivid 250D and Vivid 500 (not in this manual); any Fujifilm spectral sensitivity, dye density, MTF or granularity data. Brian Pritchard's datasheet page (https://brianpritchard.com/wp/british-motion-picture-laboratories/datasheets/) loaded but exposed no Fujifilm PDF links to a scripted fetch; it should be browsed by hand.
- **3513 gamma:** the manual gives no gamma. The "ASC: 3513 gamma 2.6" quote stays unused until someone finds a primary source; a gamma can instead be measured from the manual's chart, after undoing the 1.0 log H shift.

## Standards used with these curves

| Document | Revision | What it gives | Access | URL |
| --- | --- | --- | --- | --- |
| SMPTE RP 180 | 1999 (archived 2006) | Printing-density responsivities, 10 nm table (peaks B 430, G 530, R 670 nm) | Free PDF | https://pub.smpte.org/pub/rp180/rp0180-1999_stable2006.pdf |
| SMPTE ST 2065-2 (APD) | 2020 | Academy Printing Density responsivities, 2 nm CSV (`st2065-2a-2020.csv`), influx spectrum CSV | Free zip | https://pub.smpte.org/latest/st2065-2/ |
| SMPTE ST 2065-3 (ADX) | 2020 | ADX10/ADX16 encoding of APD | Free zip | https://pub.smpte.org/latest/st2065-3/ |
| SMPTE ST 196 | 2003 | Theater screen luminance 55 cd/m², 5400 K xenon, stray light < 0.16% / 0.25% | Free zip | https://pub.smpte.org/latest/st196/ |
| ISO 5-3 | 2009 | Status A, Status M (and other) spectral products | **Paywalled**; only the public preview was read | https://standards.iteh.ai/catalog/standards/iso/6cdfb60e-5093-43ae-b7a4-7102bd9170bd/iso-5-3-2009 |

## Licenses and trademarks

- **Kodak documents** are © Eastman Kodak Company with no license grant. Each sheet lists trademarks, e.g. "Kodak, Keykode, Vision, and Wratten and the Kodak logo are trademarks" (H-1-5207) and "Kodak, Estar, Vision, and Wratten…" (H-1-2383); the Ektachrome sheet adds EKTACHROME. **Do not commit the PDFs.** Digitized curve values are factual measurements, but whether we may publish them in an Apache-2.0 repo is a legal question (MOV-87, MOV-94). Product names stay out of the app (MOV-92).
- **Fujifilm documents** are © Fujifilm; ETERNA, REALA and FUJICOLOR are Fujifilm marks. Our only copies are third-party mirrors, so their availability can change. Same rules as Kodak.
- **SMPTE documents** are © SMPTE and offered free at pub.smpte.org. Using the RP 180 and APD responsivity tables as data inside the engine needs a license check before we ship the tables (MOV-94). **[Unverified: SMPTE's terms for redistributing the CSVs]**
- **ISO 5-3** is paywalled; we hold no copy of its tables.

## Archive

The PDFs are kept **outside git** (license above) in `~/Documents/Emulsion Research/Film science 2026-11-07/` on the owner's machine. This is a local archive, not a redistribution license. SHA-256 lets anyone confirm they hold the same file:

| File | SHA-256 |
| --- | --- |
| KODAK-VISION3-50D-5203-7203-technical-information.pdf (Mar 2026) | `b4613661abed641671329eff3bd7d5686b268eb26b954ef1c27ea68f363caca6` |
| VISION3_50D_5203_TI-2657_Technical-Data_EN.pdf (Mar 2022) | `17abe14a5ec417a44ff76e5dc64f5d1391080116cc062d1ea74080e654320d73` |
| KODAK-VISION3-200T-5213-7213-technical-information.pdf (Mar 2026) | `6208b3938416434bb74fc628d102b59cd60cb1704510202496b46197796ec624` |
| KODAK-VISION3-250D-5207-7207-technical-information.pdf (Mar 2026) | `70adb298a7aabb285d986b720e07c87c27eb2361f0925aea2b15903c08282e16` |
| VISION3-250D-Technical-Data-EN.pdf (Mar 2022) | `69094a9cecdfe2fae752a96c1f471bddf1cb514c83513757b6587a3de6432799` |
| KODAK-VISION3-5219-7219-technical-information.pdf (Mar 2026) | `6d037d8090373ee50d10bedfff3df14777a575dd107c50edcafc7ec5862d0972` |
| VISION3-500T-Color-Negative-Film-7219-TECHNICAL-DATA.pdf (Jul 2015) | `06eca2287fbaf57a1aeacbb8151bbd48e23aefb30af2114b412e9c1c63f4d1db` |
| KODAK-VISION-Color-Print-Film-2383-3383-technical-information.pdf (Aug 2026) | `a72fa4482ebd891a9ac4a823cafe740e3587c56470f27e4dfd4391f5c3e5a207` |
| KODAK-VISION-Color-Print-Film-2383-3383-data-sheet.pdf (Mar 2022) | `181eecf54c11da2dab995ffc230a549d675883bd30cced41e7d823302c2c4db2` |
| VISPREM.PDF (2393, Sept 1998) | `e1dbdfa64e80a1fde9e638a9e1ac1da394a5febafa6b39b2ed8b8a2aa087c82f` |
| LAD-for-KODAK-VISION-Color-Print-Film-H-61b.pdf | `56eab4bb2e7fef2e52d6be113e83fc0c222d429a81b7a86d95e51eac51d4b229` |
| EKTACHROME-100D-sell-sheet-EN.pdf (May 2024) | `5349fc785d62339431afee3ae5bd5e1f83aeee360293a9c47fadeefd15ee7499` |
| DOUBLEX-Technical-Data-EN.pdf (Mar 2022) | `5ac74c3084d36170b0eaaa85606df3c7a866406155fbc0c43dd5b3c7b2e0e839` |
| 076_fujifilm_motion_picture_film_manual.pdf (KB-0707E) | `76c44cb30ce447eff57bc88743f10bcfdd62cfa55825323b82d1926c6fe3f44a` |
| ETERNA250_product_info.pdf (2005) | `d280d3c5669acaf26c87e90a83308f93fe1b3a6bc11d2eb8883fdbe556808136` |
| rp0180-1999_stable2006.pdf | `2cfe24720854a840f3c67640a156938bd407ec99af56311a72ccf577d54721d2` |
| st2065-2-2020.pdf | `63b6d267db5083f6153d6f604a472fbfd53486a970595526f3d17ba7efbe7897` |
| st2065-3-2020.pdf | `fb6949a21d729494ad71fc848f9df667c56c29ead0e1357e38ed224f1856d764` |
| st0196-2003.pdf | `f7f2f3c8f216b5c9c34355a0ad7f19e325470051ba41cf7481dd395bf505b1e5` |

## What to digitize first (recommendation)
1. **250D (H-1-5207)**: characteristic (Status M), spectral sensitivity, dye density *including* Midscale Neutral and Minimum Density (needed to rebuild the mask, MOV-88).
2. **2383 (H-1-2383, Aug 2026)**: characteristic (Status A) and the redrawn dye chart.
3. **500T (H-1-5219)**: same set as 250D; confirm its densitometry (both sheets mislabel it "ECN-2").
4. **ETERNA-CP 3513DI**: characteristic only, after undoing the 1.0 log H shift, as a second print look.
