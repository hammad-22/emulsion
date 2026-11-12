# MOV-79 proof: RAW develop keeps highlight headroom

Every image is rendered through the film look with `Adjustments.neutral` (no grain or halation), Display P3, 8-bit.
"Before" is the RAW configuration the Developer used before MOV-79 (Apple's look processing off, gamut mapping and shadow bias at the file's defaults). "After" is `Developer.develop` now.
Regenerate with `EMULSION_PROOF_DIR=<dir> EMULSION_RAW_SAMPLES=<dir> swift test --filter RAWDevelopProofRenders` in `Packages/EmulsionCore`.

## Synthetic wedge and chart (`wedge-before.png`, `wedge-after.png`)

A Bayer DNG with BaselineExposure 2. The top two rows hold a half-stop neutral wedge, 0.18 × 2^s scene light for s = −4…+3.5 (developed 0.045…16.3). The bottom row holds six chromatic patches and two Display P3 colours outside sRGB.

- **Before:** from the second patch of the second row on (scene light ≥ 1.0 after BaselineExposure), every patch prints the same light grey (code 216). Apple's gamut mapping caps the develop near 1.0, so the top 3 stops of the wedge are lost. The chromatic patches are washed out toward pastel: the saturated red prints (212, 124, 117) and the P3 red prints (213, 137, 139). The shadows print darker (first patch code 30 against 45 after) because shadow bias 5 bends them on this uncalibrated camera.
- **After:** the wedge keeps rising to the last patch (216 → 228 → 237 → 242 → 246 → 248 → 251), and the colours keep their saturation: the red prints (231, 71, 69), the P3 red (225, 33, 22) and the cyan (47, 194, 235).

What the synthetic tests measured (`RAWDevelopTests`, Bayer and linear files, macOS 27.2):

| Check | Worst measured | Tolerance |
| --- | ---: | ---: |
| Unclipped neutrals vs camera value / AsShotNeutral × 2^BaselineExposure (relative, BaselineExposure 0 and 2) | 0.0024 | 0.005 |
| Unclipped neutrals, max of \|R/G − 1\|, \|B/G − 1\| | 0.0021 | 0.0045 |
| Brightest unclipped neutral at BaselineExposure 3 (expected 5.76) | 0.0016 | 0.005 |
| Image max at BaselineExposure 3 (before: 1.19 Bayer, 1.11 linear) | 16.3–16.7 | > 4.0 |
| Clipped neutrals rebuilt by highlight recovery, \|R/G − 1\|, \|B/G − 1\| | 0.0222 | 0.045 |
| Chromatic patches vs the camera-matrix value, absolute, linear sRGB | 0.0016 | 0.0035 |
| Draft half-size develop vs full develop (relative to max(1, value)) | 0.0012 | 0.0025 |
| Film render of the developed chart (BaselineExposure 3), encoded P3 | 0.057…0.992 | within 0…1 |

## Real files (`*_CC0-before.png`, `*_CC0-after.png`)

Only the two CC0 samples are rendered here. Neither has much light above 1.0, so the pairs look almost the same.

- `iPhone12Pro_ProRAW_CC0`: max code difference 4, 5 % of pixels differ by more than 2 codes (slightly more saturated sky). The develop never exceeds 0.82, so there was nothing to clip.
- `Pixel8Pro_CC0`: max code difference 17 in 0.4 % of pixels, all in the brightest sunset clouds, which now go above 1.0 (max 1.95) instead of stopping at 1.15.

Sources and licences: `iPhone12Pro_ProRAW_CC0.DNG` is raw.pixls.us id 4264; `Pixel8Pro_CC0.dng` is raw.pixls.us id 7751. Both are CC0.

## Measured on 25 real DNGs (`RAWDevelopRealFileTests`)

22 iPhone 15 Pro Max ProRAW files, one iPhone 14 Pro ProRAW, one iPhone 12 Pro ProRAW and one Pixel 8 Pro Bayer DNG, developed at a 1024 px long edge. Old max is the pre-MOV-79 configuration; the other columns are today's develop. The last three columns are the fraction of pixels whose brightest channel exceeds 1, 2 and 4. The samples are not in the repo.

| File | BaselineExposure | Old max | New max | New p99.9 lum | > 1 | > 2 | > 4 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 0.7267 | 1.018 | 1.608 | 0.7235 | 0.0002213 | 0 | 0 |
| Divers_20231116-194855.dng | 0.5712 | 1.168 | 2.033 | 1.289 | 0.005007 | 1.272e-06 | 0 |
| Divers_20231116-195226.dng | 0.1096 | 1 | 1.076 | 1.034 | 0.001668 | 0 | 0 |
| Divers_20231116-195732.dng | 0.9699 | 1.085 | 1.873 | 0.9221 | 0.001197 | 0 | 0 |
| Divers_20231116-195900.dng | 0.2577 | 1.05 | 1.073 | 0.97 | 0.001203 | 0 | 0 |
| Divers_20231119-152101.dng | 0.5781 | 1.004 | 1.204 | 0.4302 | 5.976e-05 | 0 | 0 |
| Divers_20240409-190316.dng | 3.646 | 1.071 | 9.355 | 2.249 | 0.02086 | 0.008755 | 0.0003166 |
| Divers_20240409-190733.dng | 0.5169 | 1.012 | 1.367 | 0.8793 | 0.0006612 | 0 | 0 |
| Divers_20240510-124342.dng | 0.5389 | 1.006 | 1.151 | 0.5595 | 2.67e-05 | 0 | 0 |
| Divers_20240510-124704.dng | 3.749 | 1.087 | 7.82 | 1.707 | 0.009009 | 5.849e-05 | 1.272e-05 |
| Divers_20240516-092944.dng | -0.01795 | 0.9426 | 0.9455 | 0.6958 | 0 | 0 | 0 |
| Divers_20240517-191806.dng | 3.451 | 1.071 | 10.71 | 10.48 | 0.0853 | 0.0491 | 0.02615 |
| Divers_20240518-130455.dng | 0.5277 | 1.014 | 1.328 | 1.175 | 0.00828 | 0 | 0 |
| Divers_20240518-131300.dng | 0.3232 | 1.017 | 1.188 | 0.7217 | 0.0004921 | 0 | 0 |
| Divers_20240518-134351.dng | 0.2124 | 1.052 | 1.09 | 0.8017 | 0.001456 | 0 | 0 |
| Divers_20240518-134907.dng | 3.458 | 1.159 | 10.13 | 6.024 | 0.09031 | 0.02606 | 0.00352 |
| Divers_20240518-154932.dng | 0.6006 | 1.074 | 1.41 | 1.156 | 0.01528 | 0 | 0 |
| Divers_20240519-164125.dng | 0.5768 | 0.8664 | 0.8671 | 0.3683 | 0 | 0 | 0 |
| Divers_20240519-164224.dng | 3.777 | 1.041 | 13.31 | 3.803 | 0.1517 | 0.146 | 0.003517 |
| Divers_20240615-142216.dng | 0.8671 | 1.114 | 1.764 | 1.439 | 0.005339 | 0 | 0 |
| Divers_20240615-142716.dng | 0.6909 | 1.039 | 1.563 | 0.4608 | 0.0002022 | 0 | 0 |
| Divers_20240615-143252.dng | 1.214 | 1.124 | 2.337 | 1.959 | 0.008479 | 0.004304 | 0 |
| Pixel8Pro_CC0.dng | 0.55 | 1.151 | 1.945 | 1.036 | 0.005441 | 0 | 0 |
| iPhone12Pro_ProRAW_CC0.DNG | -0.3022 | 0.8174 | 0.8178 | 0.6441 | 0 | 0 | 0 |
| iPhone14Pro_ProRAW48MP.DNG | 0.4449 | 0.9276 | 0.9279 | 0.8091 | 0 | 0 | 0 |

Every value is finite, no file's max went down, and 5 of 25 files exceed 4.0: exactly the five with BaselineExposure above 3.

"Old max" decodes each file by URL. Through `develop(data)`, the old Developer never reached the RAW decoder for 23 of these files: ImageIO types iPhone 14/15 Pro DNGs read from memory as plain TIFF, so they went down the JPEG/HEIC path (inverse film curve) and developed to maxima around 900. The developer now identifies them with a DNG type hint.

## Known limitation: 48 MP ProRAW develops dark (MOV-134)

Median luminance at a 512 px decode, Apple's default rendering against today's develop:

| File | BaselineExposure | Apple default | Develop | Stops |
| --- | ---: | ---: | ---: | ---: |
| Divers_20231119-152101.dng (48 MP) | 0.58 | 0.170 | 0.042 | −2.0 |
| Divers_20240519-164125.dng (48 MP) | 0.58 | 0.154 | 0.038 | −2.0 |
| Divers_20240518-154932.dng (48 MP) | 0.60 | 0.209 | 0.038 | −2.5 |
| iPhone14Pro_ProRAW48MP.DNG (48 MP) | 0.44 | 0.181 | 0.024 | −2.9 |
| Divers_20240516-092944.dng (12 MP) | −0.02 | 0.246 | 0.175 | −0.5 |
| Divers_20240510-124704.dng (12 MP) | 3.75 | 0.203 | 0.170 | −0.3 |
| Divers_20240519-164224.dng (12 MP) | 3.78 | 0.060 | 0.072 | +0.25 |
| iPhone12Pro_ProRAW_CC0.DNG (12 MP) | −0.30 | 0.224 | 0.135 | −0.7 |
| Pixel8Pro_CC0.dng (Bayer) | 0.55 | 0.083 | 0.066 | −0.3 |

The 48 MP files have a small BaselineExposure and, as far as we can tell (unverified), carry the rest of their brightening in the gain table that local tone mapping applies, which the developer switches off. The light is still linear and unclipped; it sits about two stops low.
