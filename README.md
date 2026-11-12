# MOV-134 proof: exposure anchor

Mac (macOS 27.2, Apple silicon), branch `hammadshahid22/mov-134-48-mp-proraw-opens-23-stops-dark-per`.
Images: the two CC0 samples through the default-off `.neutral` look at 640 px long edge.
`*-anchor-before.png` = develop without the anchor (MOV-79 develop), `*-anchor-after.png` = with it.

- `iPhone12Pro_ProRAW_CC0`: anchor +1.012 stops.
- `Pixel8Pro_CC0` (Bayer): anchor +0.521 stops.

Develop uses `boostShadowAmount = 1` (neutral; the files' default is 0.9). The linear develop is
pixel-identical with 0 or 1 (max abs difference 0 on synthetic files, iPhone12Pro_ProRAW_CC0,
iPhone14Pro_ProRAW48MP and Pixel8Pro_CC0 at 1024 px); only the anchor's profile render changes.
Against the earlier run with 0, every real-file anchor moved by at most 0.001 stops (mean 0.0004).

## Real files (`ExposureAnchorRealFileTests`, preview long edge 1024)

Median = median Rec. 709 luminance of the linear develop. Apple = untouched `CIRAWFilter` at the same size.

| File | MP | BaselineExposure | Anchor (stops) | Median before | Median after | Median Apple | log2(after ÷ Apple) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 12.19 | 0.7267 | +0.232 | 0.2528 | 0.2968 | 0.2515 | +0.239 |
| Divers_20231116-194855.dng | 48.77 | 0.5712 | +1.843 | 0.02547 | 0.09135 | 0.0811 | +0.172 |
| Divers_20231116-195226.dng | 48.77 | 0.1096 | +2.321 | 0.03615 | 0.1807 | 0.1769 | +0.030 |
| Divers_20231116-195732.dng | 48.77 | 0.9699 | +1.945 | 0.01082 | 0.04166 | 0.02796 | +0.575 |
| Divers_20231116-195900.dng | 48.77 | 0.2577 | +2.208 | 0.02488 | 0.1149 | 0.1062 | +0.114 |
| Divers_20231119-152101.dng | 48.77 | 0.5781 | +2.079 | 0.04042 | 0.1708 | 0.1613 | +0.083 |
| Divers_20240409-190316.dng | 12.19 | 3.646 | +0.068 | 0.1575 | 0.1651 | 0.1538 | +0.103 |
| Divers_20240409-190733.dng | 48.77 | 0.5169 | +1.957 | 0.04384 | 0.1702 | 0.1741 | -0.033 |
| Divers_20240510-124342.dng | 48.77 | 0.5389 | +2.537 | 0.01627 | 0.09446 | 0.1014 | -0.103 |
| Divers_20240510-124704.dng | 12.19 | 3.749 | +0.206 | 0.1698 | 0.1959 | 0.2034 | -0.054 |
| Divers_20240516-092944.dng | 12.19 | -0.01795 | +0.330 | 0.173 | 0.2175 | 0.2426 | -0.157 |
| Divers_20240517-191806.dng | 12.19 | 3.451 | +0.522 | 0.1999 | 0.2869 | 0.3256 | -0.183 |
| Divers_20240518-130455.dng | 48.77 | 0.5277 | +1.865 | 0.04799 | 0.1748 | 0.2122 | -0.279 |
| Divers_20240518-131300.dng | 48.77 | 0.3232 | +2.473 | 0.03249 | 0.1804 | 0.1764 | +0.032 |
| Divers_20240518-134351.dng | 48.77 | 0.2124 | +1.597 | 0.04655 | 0.1408 | 0.1391 | +0.018 |
| Divers_20240518-134907.dng | 12.19 | 3.458 | -0.562 | 0.1699 | 0.1151 | 0.1098 | +0.068 |
| Divers_20240518-154932.dng | 48.77 | 0.6006 | +2.406 | 0.0372 | 0.1971 | 0.205 | -0.057 |
| Divers_20240519-164125.dng | 48.77 | 0.5768 | +1.994 | 0.03735 | 0.1488 | 0.1492 | -0.004 |
| Divers_20240519-164224.dng | 12.19 | 3.777 | +0.173 | 0.06807 | 0.07675 | 0.05395 | +0.509 |
| Divers_20240615-142216.dng | 48.77 | 0.8671 | +1.752 | 0.01733 | 0.05835 | 0.04136 | +0.497 |
| Divers_20240615-142716.dng | 48.77 | 0.6909 | +1.735 | 0.03072 | 0.1022 | 0.08565 | +0.255 |
| Divers_20240615-143252.dng | 48.77 | 1.214 | +2.951 | 0.01986 | 0.1536 | 0.1488 | +0.045 |
| Pixel8Pro_CC0.dng | 49.91 | 0.55 | +0.521 | 0.06543 | 0.09386 | 0.08243 | +0.187 |
| iPhone12Pro_ProRAW_CC0.DNG | 12.19 | -0.3022 | +1.012 | 0.1357 | 0.2737 | 0.226 | +0.277 |
| iPhone14Pro_ProRAW48MP.DNG | 48.77 | 0.4449 | +2.765 | 0.02432 | 0.1653 | 0.1803 | -0.125 |

Worst |log2(after ÷ Apple)| 0.575 stops, mean 0.168. Mean log2(after ÷ Apple) of files ≥ 40 MP minus files < 20 MP: −0.017 stops.
Anchors at 1024 px and 512 px previews equal within 1e-6 on every file.

## Performance (`PerformanceProbe.testRAWDevelopTimings`, develop + materialize, median of 3 after 1 warm-up)

"before" is the MOV-79 develop (draft mode on below full size). "after" is the shipped develop
(anchor computed, draft mode off for the whole develop when the file supports local tone mapping).
The two other rows separate draft mode from the anchor's cost.

Run 1 (boostShadowAmount 0 in the develop, quiet machine):

| File | Native size | Long edge | Variant | Median ms | First ms | Anchor |
| --- | --- | ---: | --- | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | before: no anchor, draft on | 116 | 146 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | no anchor, draft off | 108 | 110 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | after: anchor, draft off | 135 | 131 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | anchor, then draft on for the output | 205 | 201 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | before: no anchor, draft on | 114 | 119 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | no anchor, draft off | 109 | 115 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | after: anchor, draft off | 135 | 138 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | anchor, then draft on for the output | 207 | 203 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | full | before: no anchor, draft on | 125 | 120 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | full | after: anchor, draft off | 152 | 150 | +0.232 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | before: no anchor, draft on | 959 | 964 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | no anchor, draft off | 958 | 957 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | after: anchor, draft off | 1018 | 1026 | +1.842 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | anchor, then draft on for the output | 1921 | 1921 | +1.842 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | before: no anchor, draft on | 964 | 1007 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | no anchor, draft off | 963 | 961 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | after: anchor, draft off | 1027 | 1065 | +1.842 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | anchor, then draft on for the output | 1934 | 1925 | +1.842 |
| Divers_20231116-194855.dng | 8064×6048 | full | before: no anchor, draft on | 1012 | 980 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | full | after: anchor, draft off | 1062 | 1058 | +1.842 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | before: no anchor, draft on | 143 | 189 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | no anchor, draft off | 140 | 130 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | after: anchor, draft off | 249 | 250 | +0.520 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | anchor, then draft on for the output | 247 | 249 | +0.520 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | before: no anchor, draft on | 137 | 142 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | no anchor, draft off | 146 | 137 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | after: anchor, draft off | 250 | 262 | +0.520 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | anchor, then draft on for the output | 243 | 259 | +0.520 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | before: no anchor, draft on | 165 | 152 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | after: anchor, draft off | 286 | 284 | +0.520 |

Run 2 (boostShadowAmount 1, the shipped develop; the machine was busier: the unchanged "before" rows are 5–20 % slower too):

| File | Native size | Long edge | Variant | Median ms | First ms | Anchor |
| --- | --- | ---: | --- | ---: | ---: | ---: |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | before: no anchor, draft on | 136 | 174 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | no anchor, draft off | 120 | 135 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | after: anchor, draft off | 161 | 152 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1024 | anchor, then draft on for the output | 225 | 222 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | before: no anchor, draft on | 157 | 142 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | no anchor, draft off | 134 | 119 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | after: anchor, draft off | 153 | 160 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | 1600 | anchor, then draft on for the output | 251 | 218 | +0.232 |
| Divers_20231101-143329.dng | 4032×3024 | full | before: no anchor, draft on | 140 | 165 | +0.000 |
| Divers_20231101-143329.dng | 4032×3024 | full | after: anchor, draft off | 171 | 184 | +0.232 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | before: no anchor, draft on | 1000 | 1052 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | no anchor, draft off | 1020 | 1049 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | after: anchor, draft off | 1127 | 1209 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | 1024 | anchor, then draft on for the output | 2123 | 2333 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | before: no anchor, draft on | 990 | 1020 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | no anchor, draft off | 974 | 967 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | after: anchor, draft off | 1803 | 1089 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | 1600 | anchor, then draft on for the output | 1984 | 2005 | +1.843 |
| Divers_20231116-194855.dng | 8064×6048 | full | before: no anchor, draft on | 1036 | 1027 | +0.000 |
| Divers_20231116-194855.dng | 8064×6048 | full | after: anchor, draft off | 1143 | 1232 | +1.843 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | before: no anchor, draft on | 166 | 177 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | no anchor, draft off | 162 | 164 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | after: anchor, draft off | 300 | 311 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1024 | anchor, then draft on for the output | 346 | 328 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | before: no anchor, draft on | 157 | 155 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | no anchor, draft off | 163 | 150 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | after: anchor, draft off | 319 | 309 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | 1600 | anchor, then draft on for the output | 299 | 303 | +0.521 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | before: no anchor, draft on | 209 | 215 | +0.000 |
| Pixel8Pro_CC0.dng | 8144×6128 | full | after: anchor, draft off | 433 | 352 | +0.521 |

Interleaved A/B of the anchor flow (thumbnails + 1024 output, same process, median of 5): 48 MP ProRAW
1143 ms with boostShadowAmount 0 vs 1154 ms with 1; Pixel 8 Pro 311 vs 335 ms (ranges overlap: 302–378 vs 296–525).

### Third timing run (final code, 11 Nov 2026, load average about 5)

| File | Long edge | Before (ms) | After (ms) |
| --- | ---: | ---: | ---: |
| 48 MP ProRAW (Divers_20231116-194855) | 1024 | 940 | 981 |
| 48 MP ProRAW | 1600 | 953 | 997 |
| 48 MP ProRAW | full | 992 | 1029 |
| Pixel 8 Pro Bayer | 1024 | 145 | 338 |
| Pixel 8 Pro Bayer | 1600 | 138 | 333 |
| Pixel 8 Pro Bayer | full | 186 | 310 |
