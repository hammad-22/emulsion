# Golden diff: new engine (MOV-25, final branch) against the origin/main (7ed4629) goldens

CIEDE2000 per pixel on the 16-bit Display P3 output, with the suite's own render (`VisualRegression.render`), golden store and comparison (`VisualRegression.compare`, `ColorDifference.Summary`). Thresholds: mean ≤ 0.2, p95 ≤ 0.5, max ≤ 1.0 (local tone on the photos: p99.9).

**Overall** (all 567907 pixels of 43 cases pooled): mean 1.3101, p95 2.4657, max 10.1485.

Worst by mean: primaries.exposure-minus2 (mean 4.913, p95 9.169, max 9.703); primaries.cool (mean 4.010, p95 9.290, max 10.149); primaries.neutral (mean 3.882, p95 9.169, max 9.703).

| Case | Mean | p95 | Max | Verdict vs old goldens |
| --- | ---: | ---: | ---: | --- |
| wedge.neutral | 0.5547 | 1.7110 | 1.8134 | fail |
| wedge.exposure-plus2 | 0.5152 | 1.7110 | 1.8134 | fail |
| wedge.exposure-minus2 | 0.5951 | 1.7110 | 1.8134 | fail |
| wedge.warm | 0.7113 | 1.6134 | 1.7015 | fail |
| wedge.cool | 0.7507 | 1.7727 | 1.9332 | fail |
| wedge.color-plus | 0.5547 | 1.7110 | 1.8134 | fail |
| wedge.color-minus | 0.5547 | 1.7110 | 1.8134 | fail |
| chart24.neutral | 2.4935 | 5.6293 | 6.2534 | fail |
| chart24.exposure-plus2 | 1.5136 | 3.7553 | 4.6299 | fail |
| chart24.exposure-minus2 | 2.6485 | 6.0418 | 6.3326 | fail |
| chart24.warm | 2.7009 | 5.3936 | 5.9583 | fail |
| chart24.cool | 2.6343 | 6.0261 | 6.6248 | fail |
| chart24.color-plus | 2.8548 | 7.4206 | 8.9655 | fail |
| chart24.color-minus | 1.8049 | 3.5018 | 3.5034 | fail |
| primaries.neutral | 3.8822 | 9.1687 | 9.7030 | fail |
| primaries.exposure-plus2 | 2.6536 | 9.1687 | 9.7030 | fail |
| primaries.exposure-minus2 | 4.9133 | 9.1687 | 9.7030 | fail |
| primaries.warm | 3.7806 | 9.0664 | 9.2248 | fail |
| primaries.cool | 4.0099 | 9.2901 | 10.1485 | fail |
| primaries.color-plus | 3.6550 | 8.5643 | 9.5108 | fail |
| primaries.color-minus | 2.8510 | 5.0609 | 5.1778 | fail |
| skin-like.neutral | 1.4245 | 1.7523 | 1.7523 | fail |
| skin-like.exposure-plus2 | 0.9964 | 1.7523 | 1.7523 | fail |
| skin-like.exposure-minus2 | 1.6791 | 2.3787 | 2.3787 | fail |
| skin-like.warm | 1.1642 | 1.5057 | 1.5057 | fail |
| skin-like.cool | 1.9694 | 2.5895 | 2.5895 | fail |
| skin-like.color-plus | 1.4655 | 1.7790 | 1.7790 | fail |
| skin-like.color-minus | 1.1261 | 1.6750 | 1.6750 | fail |
| highlight-point.halation | 1.7690 | 1.7717 | 1.8749 | fail |
| highlight-point.halation-exposed | 1.2257 | 1.2266 | 1.9380 | fail |
| gradient.localtone-recover | 1.1654 | 2.9654 | 3.4689 | fail |
| gradient.localtone-contrast | 0.7794 | 1.6179 | 1.8860 | fail |
| gradient.default-look | 0.9479 | 1.8420 | 2.2617 | fail |
| gradient.grain | 0.9407 | 1.8366 | 2.1509 | fail |
| display-chart.neutral | 0.0073 | 0.0216 | 0.0287 | pass |
| display-chart.exposure-plus2 | 1.8308 | 6.9462 | 6.9906 | fail |
| display-chart.exposure-minus2 | 2.4269 | 5.2994 | 10.1311 | fail |
| iphone12pro-proraw.default-look | 1.1825 | 2.0302 | 4.9478 | fail |
| iphone12pro-proraw.graded | 1.1065 | 2.6177 | 8.4900 | fail |
| iphone12pro-proraw.localtone | 1.1202 | 2.0152 | 6.2221 | fail |
| pixel8pro-dng.default-look | 1.6346 | 2.2666 | 4.3925 | fail |
| pixel8pro-dng.graded | 1.8271 | 2.5984 | 5.8130 | fail |
| pixel8pro-dng.localtone | 1.7057 | 2.4828 | 7.8442 | fail |
