# MOV-10 proof: RAW white balance (macOS 27.2, Mac)

Renders go through the neutral film look (`Adjustments.neutral`), long edge ≤ 640 px.

## Synthetic chart (wide-gamut synthetic camera, Bayer)

A 2856 K Planckian light (Kim et al. 2002 chromaticity) on 4 gray + 8 chromatic patches.
- `wb-wrong-tag-before.png`: the file tagged as D65, developed as shot: strong orange cast.
- `wb-wrong-tag-after.png`: the same file developed at 2856 K, tint 0: grays neutral.
- `wb-right-tag-reference.png`: the file tagged with the 2856 K neutral, as shot (reference).

| Measurement (worst of Bayer and linear) | Measured | Tolerance |
| --- | ---: | ---: |
| As-shot temperature, tagged 2856 K / D65 (6504 K) | 2862.8 / 6502.0 K | ±15 K |
| As-shot tint, tagged 2856 K / D65 (expected 0 / 9.52 = 3000 × Duv) | 0.245 / 9.77 | ±0.5 |
| Gray neutral error, correctly tagged, as shot | 0.0012 | 0.0025 |
| Gray neutral error, tagged D65, as shot | 1.22 | > 1 required |
| Gray neutral error, tagged D65, at 2856 K tint 0 | 0.0053 | 0.011 |
| vs correctly tagged develop at 2856 K (gray / chromatic, relative) | 0.0053 / 0.0183 | 0.037 |
| vs correctly tagged develop at its read-back 2862.8 K, 0.245 | 0.0056 (Bayer), 2.5e-5 (linear) | 0.012 |
| As-shot values set explicitly (absolute) | 7.4e-6 | 2e-5 |
| Draft half-size vs full, with white balance | 0.0009 | 0.002 |
| Exposure anchor at 3200 K / 6500 K +20 / 10000 K −20 | identical (2.0000078 linear, 2.0002987 Bayer) | exact |

Temperature sweep on the tungsten file tagged D65 (gray patch, linear): R/G 0.746, 1.205, 1.553, 1.853, 2.128, 2.294, 2.424 and B/G 1.335, 0.797, 0.538, 0.380, 0.265, 0.207, 0.163 at 2500, 3200, 4000, 5000, 6500, 8000, 10000 K.

## Real files (CC0 only rendered): as shot, × 0.75 (cooler), × 1.35 (warmer) of the as-shot temperature

- Pixel8Pro_CC0: 6019 K tint −7.7 → 4514 K / 8126 K
- iPhone12Pro_ProRAW_CC0: 5201 K tint 6.4 → 3901 K / 7022 K

## All real files (1024 px; ratios are frame means of linear develop; max diff relative to max(1, value))

| File | As shot K | Tint | R/G, B/G as shot | R/G, B/G 3200 K | R/G, B/G 6500 K | Max rel. diff, as-shot values set | Anchor (as shot / 3200 / 6500) |
| --- | ---: | ---: | --- | --- | --- | ---: | --- |
| Divers_20231101-143329.dng | 4441 | 19.08 | 0.6459, -0.1972 | 0.3865, -0.08794 | 0.8447, -0.2096 | 4.127e-07 | +0.2317 / +0.2317 / +0.2317 |
| Divers_20231116-194855.dng | 2853 | 10.79 | 1.426, 0.6668 | 1.684, 0.4999 | 2.643, 0.1366 | 2.654e-07 | +1.8426 / +1.8426 / +1.8426 |
| Divers_20231116-195226.dng | 3374 | 18.15 | 1.142, 0.8219 | 1.069, 0.9168 | 1.844, 0.3265 | 1.959e-06 | +2.3212 / +2.3212 / +2.3212 |
| Divers_20231116-195732.dng | 3155 | 10.05 | 1.209, 0.7704 | 1.229, 0.7474 | 2.062, 0.2551 | 0.0001469 | +1.9447 / +1.9447 / +1.9447 |
| Divers_20231116-195900.dng | 2694 | 10.43 | 1.435, 0.6238 | 1.876, 0.3785 | 2.951, 0.07066 | 7.714e-07 | +2.2079 / +2.2079 / +2.2079 |
| Divers_20231119-152101.dng | 5086 | 4.301 | 1.042, 0.9646 | 0.5963, 1.761 | 1.185, 0.7793 | 2.873e-06 | +2.0795 / +2.0795 / +2.0795 |
| Divers_20240409-190316.dng | 4512 | 2.163 | 0.985, 0.471 | 0.6389, 0.8551 | 1.214, 0.3092 | 1.469e-06 | +0.0680 / +0.0680 / +0.0680 |
| Divers_20240409-190733.dng | 5201 | 5.493 | 0.9538, 1.072 | 0.5195, 1.974 | 1.076, 0.8897 | 4.754e-06 | +1.9572 / +1.9572 / +1.9572 |
| Divers_20240510-124342.dng | 5122 | 7.911 | 0.8054, 1.251 | 0.4105, 2.271 | 0.9314, 1.021 | 3.776e-06 | +2.5373 / +2.5373 / +2.5373 |
| Divers_20240510-124704.dng | 5236 | 8.462 | 0.7822, 1.369 | 0.393, 2.471 | 0.8874, 1.154 | 5.107e-06 | +0.2062 / +0.2062 / +0.2062 |
| Divers_20240516-092944.dng | 4881 | -1.711 | 1.106, 0.8665 | 0.6768, 1.497 | 1.279, 0.6774 | 1.55e-06 | +0.3301 / +0.3301 / +0.3301 |
| Divers_20240517-191806.dng | 4951 | -0.2774 | 1.036, 0.9133 | 0.6592, 1.523 | 1.177, 0.7413 | 1.16e-06 | +0.5218 / +0.5218 / +0.5218 |
| Divers_20240518-130455.dng | 5091 | 5.243 | 0.9454, 1.115 | 0.5344, 1.946 | 1.077, 0.9135 | 2.936e-06 | +1.8651 / +1.8651 / +1.8651 |
| Divers_20240518-131300.dng | 2717 | 8.143 | 1.12, 0.9239 | 1.462, 0.6329 | 2.41, 0.1946 | 9.399e-07 | +2.4730 / +2.4730 / +2.4730 |
| Divers_20240518-134351.dng | 5295 | 7.273 | 1.131, 0.9524 | 0.6351, 1.823 | 1.252, 0.8005 | 5.469e-06 | +1.5972 / +1.5972 / +1.5972 |
| Divers_20240518-134907.dng | 3435 | 9.11 | 0.9314, 1.108 | 0.844, 1.253 | 1.525, 0.5026 | 2.595e-06 | -0.5620 / -0.5620 / -0.5620 |
| Divers_20240518-154932.dng | 5080 | 7.665 | 0.9584, 1.06 | 0.5426, 1.869 | 1.093, 0.863 | 2.793e-06 | +2.4057 / +2.4057 / +2.4057 |
| Divers_20240519-164125.dng | 5036 | 6.523 | 0.9892, 1.152 | 0.5543, 2.062 | 1.14, 0.9233 | 1.436e-06 | +1.9942 / +1.9942 / +1.9942 |
| Divers_20240519-164224.dng | 5248 | 9.319 | 0.8421, 1.136 | 0.427, 2.153 | 0.9544, 0.9466 | 5.288e-06 | +0.1732 / +0.1732 / +0.1732 |
| Divers_20240615-142216.dng | 2976 | 1.701 | 1.457, 0.6896 | 1.607, 0.5933 | 2.515, 0.1953 | 0.0001105 | +1.7515 / +1.7515 / +1.7515 |
| Divers_20240615-142716.dng | 3004 | 6.594 | 1.226, 0.81 | 1.34, 0.7065 | 2.251, 0.2249 | 9.876e-05 | +1.7345 / +1.7345 / +1.7345 |
| Divers_20240615-143252.dng | 3188 | 4.255 | 1.62, 0.5869 | 1.626, 0.5823 | 2.536, 0.1813 | 0.0001599 | +2.9510 / +2.9510 / +2.9510 |
| Pixel8Pro_CC0.dng | 6019 | -7.71 | 1.024, 1.114 | 0.4645, 2.003 | 1.079, 1.063 | 1.802e-06 | +0.5206 / +0.5206 / +0.5206 |
| iPhone12Pro_ProRAW_CC0.DNG | 5201 | 6.358 | 0.8335, 1.286 | 0.4313, 2.304 | 0.9467, 1.077 | 3.036e-06 | +1.0125 / +1.0125 / +1.0125 |
| iPhone14Pro_ProRAW48MP.DNG | 5622 | 14.46 | 0.8691, 1.086 | 0.4096, 2.243 | 0.94, 0.963 | 2.302e-06 | +2.7646 / +2.7646 / +2.7646 |

Worst as-shot repeat: 1.6e-4 (tolerance 4e-4). Anchor identical at every setting on all 25 files; R/B(3200 K) < R/B(6500 K) on all 25.

## Performance (Mac, 1024 px unless stated; first DNG per make and size)

These tables were removed from docs/ENGINE.md; ENGINE.md keeps one line (a new white balance re-develops, about 1 s for 48 MP at 1024 px; a kept-alive filter about 30 ms).

### `PerformanceProbe.testRAWDevelopTimings` (develop + materialize, after the review fixes; "after, 3200 K" is the white-balance variant)

| File | Native size | Long edge | Variant | Median ms | First ms | Anchor |
| --- | --- | ---: | --- | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | before | 110 | 142 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | after | 127 | 133 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | after, 3200 K | 125 | 130 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | before | 110 | 109 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | after | 130 | 129 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | after, 3200 K | 131 | 128 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | full | before | 119 | 117 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | full | after | 146 | 147 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | full | after, 3200 K | 142 | 142 | +0.232 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | before | 927 | 923 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | after | 983 | 980 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | after, 3200 K | 981 | 977 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | before | 935 | 929 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | after | 980 | 969 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | after, 3200 K | 984 | 997 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | full | before | 959 | 950 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | full | after | 1007 | 1012 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | full | after, 3200 K | 1008 | 1016 | +1.843 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | before | 154 | 140 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | after | 399 | 397 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | after, 3200 K | 399 | 393 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | before | 145 | 151 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | after | 396 | 405 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | after, 3200 K | 394 | 391 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | before | 214 | 210 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | after | 472 | 462 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | after, 3200 K | 481 | 465 | +0.521 |

Reading `Negative.asShotWhiteBalance` during the develop costs nothing measurable (same run with the read replaced by nil: 129/127, 989/994, 396/388 ms at 1024 px for after / after 3200 K). The Pixel 8 Pro "after" time (about 395 ms) is higher than the 239 ms in the earlier one-off table below on this run and with the read removed alike, so it is not from these changes; unexplained, worth re-measuring.

### Earlier one-off measurements (removed from the probe; first commit of MOV-10)

Develop at 1024 px with and without a white balance; output render alone after the anchor (does a new white balance throw away the decode; before vs after the preview scale); one kept-alive ("warm") filter re-rendered at a new temperature.


| File | Native size | Develop, as shot (median / first ms) | Develop, 3200 K (median / first ms) |
| --- | --- | ---: | ---: |
| Divers_20231101-143329.dng | 4032×3024 | 126 / 163 | 128 / 126 |
| Divers_20231116-194855.dng | 8064×6048 | 971 / 967 | 974 / 975 |
| Pixel8Pro_CC0.dng | 8144×6128 | 239 / 243 | 239 / 234 |

| File | Output render after the anchor: as shot | 3200 K after scale | 3200 K before scale (median ms) | Max diff, before vs after scale |
| --- | ---: | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 9 | 9 | 10 | 0 |
| Divers_20231116-194855.dng | 26 | 28 | 27 | 0 |
| Pixel8Pro_CC0.dng | 50 | 47 | 46 | 0 |

| File | Long edge | First render ms | New temperature, re-render (median / max ms of 8) |
| --- | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 1024 | 75 | 7 / 10 |
| Divers_20231101-143329.dng | 1600 | 83 | 12 / 14 |
| Divers_20231116-194855.dng | 1024 | 883 | 27 / 30 |
| Divers_20231116-194855.dng | 1600 | 892 | 33 / 34 |
| Pixel8Pro_CC0.dng | 1024 | 115 | 49 / 50 |
| Pixel8Pro_CC0.dng | 1600 | 109 | 52 / 58 |
