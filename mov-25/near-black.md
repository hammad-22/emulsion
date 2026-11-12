# MOV-25: display-referred photos near black, before vs after

Before: origin/hammadshahid22/mov-108-fit-tool-2-emulsion-fit-cli-and (e6c0ddd, logistic negative).
After (−9): the MOV-25 branch as first submitted (ee601c1, toe-and-shoulder negative + printing-density matrix, display floor −9 stops).
Final (−6): the same with `FilmLook.displayFloorStops` (and the kernel constant) moved to −6 stops, chosen by the sweep below.

Input: Display P3, 8-bit codes 0…24, one row: gray (c,c,c), tint A (c,c+1,c), tint B (c+2,c,c+1); developed with
`developer.sceneFromDisplay`, materialized, rendered with `Renderer.render` (full GPU path). Output: encoded Display P3 ×255.
"max step" is the largest increase between adjacent input codes over 0…24, any channel. Spread = max(R,G,B) − min on the gray ramp, 0…24.
The image is 1 px high, so local tone applies pointwise (its base is the pixel itself): the largest lift it can give.

## Summary (gray ramp; tints behave the same)

| edit | before: max step (at) | after −9: max step (at) | final −6: max step (at) | output of code 0 → 1: before / −9 / −6 | gray spread: before / −9 / −6 | monotone |
| --- | --- | --- | --- | --- | --- | --- |
| neutral | 1.00 (22→23) | 1.01 (23→24) | 1.01 (23→24) | 0→1 / 0→1 / 0→1 | 0.00 / 0.00 / 0.00 | yes |
| exposure +1 | 1.73 (22→23) | 1.92 (5→6) | 1.90 (17→18) | 1→2 / 0→2 / 2→3 | 0.44 / 0.54 / 0.54 | yes |
| exposure +2 | 2.94 (18→19) | 4.30 (0→1) | 3.22 (17→18) | 2→3 / 0→5 / 6→9 | 1.07 / 1.31 / 1.31 | yes |
| exposure +3 | 4.63 (17→18) | 11.36 (0→1) | 4.83 (0→1) | 4→6 / 1→12 / 18→23 | 1.83 / 2.35 / 2.35 | yes |
| shadows +1 | 17.76 (0→1) | 17.76 (0→1) | 17.75 (0→1) | 0→18 / 0→18 / 0→18 | 0.00 / 0.00 / 0.00 | yes |
| exposure +2, shadows +1 | 8.95 (0→1) | 32.19 (0→1) | 6.85 (0→1) | 24→33 / 6→38 / 43→49 | 1.58 / 2.62 / 2.32 | yes |

Final vs before, rule bound 1.1×: +2 EV 3.22 ≤ 3.23, +3 EV 4.83 ≤ 5.09, +2 EV with shadows +1 6.85 ≤ 9.85; monotone everywhere.
Trade-off: lifting edits raise display black more than before (code 0 at +3 EV: 4 before, 18.5 final; at +2 EV with shadows +1: 24 before, 43 final).

## Cause (confirmed)

The fitted negative leaves the neutral print flat below about −6 stops. F_n (display-linear green of the neutral print) by scene stops:
−10: 0.00200, −9: 0.00201, −8: 0.00203, −7: 0.00208, −6: 0.00224, −5: 0.00273, −4: 0.00417, −3: 0.00852.
At floor −9, display code 0 is estimated at −9.00 stops and code 1 at −6.44 (codes 2, 3: −5.83, −5.46): 2.6 stops between
adjacent codes, which an exposure edit then prints apart (4.30 codes at +2 EV, 11.36 at +3 EV, 32.19 at +2 EV with shadows +1, all at 0→1).

## Floor sweep (FilmLook.displayFloorStops and the kernel constant, metallibs rebuilt per value)

Gray ramp codes 0…24, Display P3, GPU render, materialized negative. Step: largest adjacent-code output step (codes), at 0→1 unless noted.
"0→1 out": output (green, float codes) of input codes 0 and 1. Neutral repro: max |out − in| over gray 0…255 at zero edits.

| floor | F_n(floor) | estimate of codes 0/1/2/3 (stops) | +1 EV | +2 EV | +3 EV | shadows +1 | +2 EV, sh +1 | 0→1 out at +1/+2/+3/sh+1/+2&sh+1 | spread (+3 EV / +2&sh+1) | monotone | neutral repro | passes rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| −9 | 0.002009 | −9.00/−6.44/−5.83/−5.46 | 1.92 (5→6) | 4.30 | 11.36 | 17.76 | 32.19 | 0.06→1.87 / 0.23→4.47 / 0.75→12.08 / 0→17.76 / 5.44→37.42 | 2.35 / 2.62 | yes | 0.055 | no |
| −8 | 0.002026 | −8.00/−6.35/−5.79/−5.44 | 1.92 (5→6) | 4.16 | 10.80 | 17.75 | 26.54 | 0.17→1.96 / 0.70→4.83 / 2.30→13.10 / 0→17.75 / 14.06→38.60 | 2.35 / 4.62 | yes | 0.055 | no |
| −7.5 | 0.002044 | −7.50/−6.26/−5.74/−5.41 | 1.91 (5→6) | 4.03 | 10.22 | 17.76 | 21.64 | 0.30→2.06 / 1.22→5.24 / 3.99→14.21 / 0→17.76 / 20.05→39.86 | 2.35 / 4.40 | yes | 0.055 | no |
| −7 | 0.002078 | −7.00/−6.11/−5.66/−5.36 | 1.90 (17→18) | 3.83 | 9.23 | 17.76 | 16.40 | 0.53→2.25 / 2.13→5.96 / 6.90→16.02 / 0→17.76 / 26.91→41.86 | 2.35 / 3.88 | yes | 0.055 | no |
| −6.5 | 0.002136 | −6.50/−5.91/−5.54/−5.27 | 1.90 (17→18) | 3.54 | 7.23 | 17.75 | 11.31 | 0.92→2.57 / 3.69→7.23 / 11.82→18.89 / 0→17.75 / 34.56→44.91 | 2.35 / 3.14 | yes | 0.055 | no |
| **−6** | 0.002238 | −6.00/−5.63/−5.36/−5.15 | 1.90 (17→18) | 3.22 (17→18) | 4.83 | 17.75 | 6.85 | 1.60→3.13 / 6.37→9.46 / 18.51→23.30 / 0→17.75 / 42.89→49.26 | 2.35 / 2.32 | yes | 0.055 | **yes (deepest)** |
| −5.5 | 0.002416 | −5.50/−5.29/−5.11/−4.95 | 1.90 (17→18) | 3.20 (17→18) | 4.72 (14→15) | 17.73 | 3.40 | 2.77→4.11 / 10.96→13.12 / 27.06→29.77 / 0→17.73 / 51.69→54.97 | 2.35 / 1.90 | yes | 0.055 | yes |
| −5 | 0.002725 | −5.00/−4.89/−4.79/−4.69 | 1.90 (17→18) | 3.20 (17→18) | 4.63 (14→15) | 17.76 | 1.92 (6→7) | 4.77→5.85 / 17.43→18.38 / 38.05→38.90 / 0→17.76 / 60.69→61.84 | 2.35 / 1.90 | yes | 0.055 | yes |

Gray spread at +1/+2 EV is 0.54/1.31 at every floor; shadows +1 spread 0.00.
Rule (before × 1.1): +2 EV ≤ 3.23, +3 EV ≤ 5.09, +2 EV with shadows +1 ≤ 9.85, monotone. −6.5 fails at +3 EV (7.23).

Side effect on bundled samples at neutral: Street Lights' flat background (source sRGB 7,13,25 = P3 8.11, 12.82, 24.08)
now renders 8,13,25 instead of 9,13,25 (closer to the source); other samples move by at most 1 code (neutral) / 2 codes (+1 EV).

## Before

### neutral

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 1/1/1 2/2/2 3/3/3 4/4/4 5/5/5 6/6/6 7/7/7 8/8/8 9/9/9 10/10/10 11/11/11 12/12/12; max step 1.00 codes (float) at 22→23, 1 (8-bit) at 0→1; monotone yes; max channel spread 0.00 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/1/0 1/2/1 2/3/2 3/4/3 4/5/4 5/6/5 6/7/6 7/8/7 8/9/8 9/10/9 10/11/10 11/12/11 12/13/12; max step 1.01 codes (float) at 0→1, 1 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 2/0/1 3/1/2 4/2/3 5/3/4 6/4/5 7/5/6 8/6/7 9/7/8 10/8/9 11/9/10 12/10/11 13/11/12 14/12/13; max step 1.05 codes (float) at 0→1, 1 (8-bit) at 0→1; monotone yes

### exposure +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 1/1/1 2/2/2 3/3/3 4/4/5 6/6/6 7/7/7 9/9/9 11/11/11 12/12/12 14/14/14 15/15/15 17/17/17 19/18/18; max step 1.73 codes (float) at 22→23, 2 (8-bit) at 2→3; monotone yes; max channel spread 0.44 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 1/2/1 2/3/2 3/4/3 4/6/5 6/7/6 7/9/7 9/11/9 11/12/11 12/14/12 14/15/14 15/17/15 17/18/17 19/20/18; max step 1.74 codes (float) at 21→22, 2 (8-bit) at 2→3; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 3/1/2 4/2/3 6/3/4 7/5/6 9/6/7 11/7/9 12/9/11 14/11/12 15/12/14 17/14/15 18/15/17 20/17/18 22/18/20; max step 1.74 codes (float) at 21→22, 2 (8-bit) at 1→2; monotone yes

### exposure +2

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 2/2/2 3/3/4 5/5/5 7/7/7 10/10/10 12/12/12 15/15/15 17/17/17 20/20/20 22/22/22 25/24/24 27/27/27 30/29/29; max step 2.94 codes (float) at 18→19, 3 (8-bit) at 3→4; monotone yes; max channel spread 1.07 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 2/3/2 3/5/4 5/7/5 7/9/8 10/12/10 12/15/12 15/17/15 17/20/17 20/22/20 22/24/22 25/27/24 27/29/27 30/32/29; max step 2.94 codes (float) at 16→17, 3 (8-bit) at 2→3; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 5/2/3 7/4/5 9/5/7 12/7/10 15/10/12 17/12/15 20/15/17 22/17/19 25/20/22 27/22/24 30/25/27 32/27/29 35/30/32; max step 2.93 codes (float) at 18→19, 3 (8-bit) at 2→3; monotone yes

### exposure +3

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 4/4/4 6/6/6 9/9/10 13/13/13 17/17/17 21/20/21 25/24/24 29/28/28 33/32/32 37/36/36 41/40/40 45/44/43 49/48/47; max step 4.63 codes (float) at 17→18, 5 (8-bit) at 12→13; monotone yes; max channel spread 1.83 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 4/6/4 6/9/7 9/13/10 13/16/13 17/20/17 21/24/21 25/28/24 29/32/28 33/36/32 37/40/36 41/44/40 45/48/44 49/52/48; max step 4.65 codes (float) at 16→17, 5 (8-bit) at 12→13; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 9/4/6 13/7/9 16/10/13 20/13/17 24/17/20 28/21/24 32/25/28 36/29/32 40/33/36 44/36/39 49/40/43 53/44/47 57/49/51; max step 4.61 codes (float) at 17→18, 5 (8-bit) at 9→10; monotone yes

### shadows +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 18/18/18 26/26/26 32/32/32 36/36/36 39/39/39 42/42/42 44/44/44 47/47/47 48/48/48 50/50/50 52/52/52 53/53/53; max step 17.76 codes (float) at 0→1, 18 (8-bit) at 0→1; monotone yes; max channel spread 0.00 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/18/0 16/27/16 25/32/25 31/36/31 35/40/35 38/42/38 41/45/41 44/47/44 46/49/46 48/50/48 49/52/49 51/54/51 53/55/53; max step 16.21 codes (float) at 0→1, 16 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 30/0/19 35/17/27 38/25/32 41/31/36 44/35/40 46/38/43 48/41/45 50/44/47 52/46/49 53/48/51 55/50/52 56/51/54 58/53/55; max step 16.21 codes (float) at 0→1, 17 (8-bit) at 0→1; monotone yes

### exposure +2, shadows +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 24/24/25 33/33/34 40/40/40 45/45/45 50/49/50 54/53/54 57/57/57 61/60/60 64/63/63 66/66/65 69/68/68 71/70/70 73/72/72; max step 8.95 codes (float) at 0→1, 9 (8-bit) at 0→1; monotone yes; max channel spread 1.58 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 23/33/24 32/40/33 38/45/39 43/50/44 48/54/48 52/58/52 56/61/56 59/64/59 62/67/61 64/69/64 67/71/66 69/73/68 71/75/70; max step 8.90 codes (float) at 0→1, 9 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 43/24/35 48/32/41 53/39/46 57/44/51 61/48/55 64/52/58 68/56/61 70/59/64 73/62/66 75/64/69 77/67/71 79/69/73 81/71/75; max step 8.68 codes (float) at 0→1, 8 (8-bit) at 0→1; monotone yes

GPU vs Swift mirror, exposure +2, all 75 inputs: max |difference| 0.000 codes (input SIMD3<Int>(22, 20, 21) channel 0: GPU 57.906 vs mirror 57.907)

## After, floor −9 (ee601c1 as first submitted)

### neutral

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 1/1/1 2/2/2 3/3/3 4/4/4 5/5/5 6/6/6 7/7/7 8/8/8 9/9/9 10/10/10 11/11/11 12/12/12; max step 1.01 codes (float) at 23→24, 1 (8-bit) at 0→1; monotone yes; max channel spread 0.00 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/1/0 1/2/1 2/3/2 3/4/3 4/5/4 5/6/5 6/7/6 7/8/7 8/9/8 9/10/9 10/11/10 11/12/11 12/13/12; max step 1.01 codes (float) at 18→19, 1 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 2/0/1 3/1/2 4/2/3 5/3/4 6/4/5 7/5/6 8/6/7 9/7/8 10/8/9 11/9/10 12/10/11 13/11/12 14/12/13; max step 1.05 codes (float) at 0→1, 1 (8-bit) at 0→1; monotone yes

### exposure +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 2/2/2 4/4/3 5/5/5 7/7/7 9/9/8 11/11/10 12/12/12 14/14/14 16/16/16 18/17/18 19/19/19 21/21/21; max step 1.92 codes (float) at 5→6, 2 (8-bit) at 0→1; monotone yes; max channel spread 0.54 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/2/0 2/3/2 4/5/3 5/7/5 7/8/7 9/10/9 11/12/11 13/14/12 14/16/14 16/17/16 18/19/18 19/21/19 21/22/21; max step 1.92 codes (float) at 5→6, 2 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 3/0/2 5/2/3 7/4/5 9/5/7 10/7/8 12/9/10 14/11/12 16/13/14 17/14/16 19/16/18 21/18/19 23/19/21 24/21/23; max step 1.92 codes (float) at 4→5, 2 (8-bit) at 0→1; monotone yes

### exposure +2

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 5/4/4 8/8/8 12/12/11 15/15/15 18/18/18 21/21/21 24/24/24 27/26/27 30/29/30 32/32/33 35/35/36 38/38/39; max step 4.30 codes (float) at 0→1, 5 (8-bit) at 0→1; monotone yes; max channel spread 1.31 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 1/3/0 5/7/4 9/11/8 12/14/12 15/17/15 18/20/18 21/23/21 24/26/24 27/29/27 30/32/30 33/35/33 35/37/36 38/40/39; max step 4.30 codes (float) at 0→1, 4 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 7/1/4 11/6/7 14/9/11 17/13/14 20/16/18 23/19/21 26/21/24 29/24/27 32/27/30 35/30/33 38/33/36 41/35/39 44/38/42; max step 4.31 codes (float) at 0→1, 5 (8-bit) at 0→1; monotone yes

### exposure +3

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 1/1/1 12/12/11 19/19/19 25/25/25 30/30/30 35/35/35 39/39/40 44/44/44 49/48/49 53/53/54 58/57/59 62/62/64 67/67/68; max step 11.36 codes (float) at 0→1, 11 (8-bit) at 0→1; monotone yes; max channel spread 2.35 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 2/8/1 13/17/12 20/23/20 26/29/25 30/34/30 35/38/35 40/43/40 45/48/45 49/52/50 54/57/54 58/61/59 63/66/64 67/71/69; max step 11.49 codes (float) at 0→1, 11 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 16/3/10 23/15/18 29/21/24 34/27/29 38/31/34 43/36/39 48/41/44 53/45/49 57/50/54 62/54/59 66/58/63 71/63/68 76/67/73; max step 11.60 codes (float) at 0→1, 12 (8-bit) at 0→1; monotone yes

### shadows +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 18/18/18 26/26/26 32/32/32 36/36/36 39/39/39 42/42/42 44/44/44 46/46/46 48/48/48 50/50/50 52/52/52 53/53/53; max step 17.76 codes (float) at 0→1, 18 (8-bit) at 0→1; monotone yes; max channel spread 0.00 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/18/0 16/27/16 25/32/25 31/36/30 35/40/35 38/42/38 41/45/41 44/47/44 46/49/46 48/50/48 49/52/49 51/54/51 53/55/53; max step 16.21 codes (float) at 0→1, 16 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 30/0/19 35/17/27 38/25/32 41/31/36 44/35/40 46/38/43 48/41/45 50/44/47 52/46/49 53/48/51 55/50/52 56/51/54 58/53/55; max step 16.21 codes (float) at 0→1, 17 (8-bit) at 0→1; monotone yes

### exposure +2, shadows +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 6/5/3 38/37/35 47/47/45 53/53/52 58/57/57 61/61/61 65/64/64 68/67/68 70/70/71 73/72/73 75/74/75 76/76/77 78/78/79; max step 32.19 codes (float) at 0→1, 32 (8-bit) at 0→1; monotone yes; max channel spread 2.62 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 9/35/7 37/46/34 46/52/44 52/57/51 56/61/55 60/65/59 63/68/63 66/70/66 69/73/69 71/75/71 73/77/73 74/78/75 76/80/77; max step 27.94 codes (float) at 0→1, 28 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 52/17/36 56/39/46 61/47/52 65/53/57 68/57/61 71/61/65 74/64/68 77/66/71 79/69/74 81/71/76 82/73/78 84/74/80 86/76/82; max step 21.60 codes (float) at 0→1, 22 (8-bit) at 0→1; monotone yes

GPU vs Swift mirror, exposure +2, all 75 inputs: max |difference| 0.000 codes (input SIMD3<Int>(20, 21, 20) channel 2: GPU 64.300 vs mirror 64.299)

## Final, floor −6

### neutral

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 1/1/1 2/2/2 3/3/3 4/4/4 5/5/5 6/6/6 7/7/7 8/8/8 9/9/9 10/10/10 11/11/11 12/12/12; max step 1.01 codes (float) at 23→24, 1 (8-bit) at 0→1; monotone yes; max channel spread 0.00 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/1/0 1/2/1 2/3/2 3/4/3 4/5/4 5/6/5 6/7/6 7/8/7 8/9/8 9/10/9 10/11/10 11/12/11 12/13/12; max step 1.01 codes (float) at 18→19, 1 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 2/0/1 3/1/2 4/2/3 5/3/4 6/4/5 7/5/6 8/6/7 9/7/8 10/8/9 11/9/10 12/10/11 13/11/12 14/12/13; max step 1.05 codes (float) at 0→1, 1 (8-bit) at 0→1; monotone yes

### exposure +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 2/2/1 3/3/3 5/5/4 6/6/6 8/8/8 9/9/9 11/11/11 13/13/13 15/15/15 16/16/16 18/18/18 19/19/20 21/21/21; max step 1.90 codes (float) at 17→18, 2 (8-bit) at 0→1; monotone yes; max channel spread 0.54 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 2/3/1 3/4/3 5/6/4 6/8/6 8/9/8 10/11/9 11/13/11 13/14/13 15/16/15 16/18/16 18/19/18 20/21/20 21/23/21; max step 1.91 codes (float) at 18→19, 2 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 4/2/3 6/3/4 8/5/6 9/6/7 11/8/9 13/10/11 14/11/13 16/13/15 18/15/16 19/16/18 21/18/20 23/20/21 24/21/23; max step 1.90 codes (float) at 16→17, 2 (8-bit) at 0→1; monotone yes

### exposure +2

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 6/6/6 10/9/9 12/12/12 15/15/14 17/17/17 20/20/20 22/22/22 25/25/25 28/27/28 30/30/31 33/33/33 36/35/36 38/38/39; max step 3.22 codes (float) at 17→18, 4 (8-bit) at 0→1; monotone yes; max channel spread 1.31 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 7/9/6 10/12/9 13/14/12 15/17/15 18/19/17 20/22/20 23/24/23 25/27/25 28/30/28 30/32/31 33/35/33 36/38/36 39/41/39; max step 3.21 codes (float) at 16→17, 4 (8-bit) at 14→15; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 12/7/9 14/10/12 17/13/14 19/16/17 22/18/20 25/20/22 27/23/25 30/25/28 33/28/30 35/31/33 38/33/36 41/36/39 44/39/42; max step 3.21 codes (float) at 16→17, 4 (8-bit) at 14→15; monotone yes

### exposure +3

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 19/19/18 23/23/23 27/27/27 31/31/31 35/35/34 38/38/38 42/42/42 46/46/47 51/50/51 55/54/55 59/58/60 63/63/64 68/67/69; max step 4.83 codes (float) at 0→1, 5 (8-bit) at 0→1; monotone yes; max channel spread 2.35 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 19/22/19 24/26/23 28/30/27 31/34/31 35/37/35 39/41/39 43/45/43 47/50/47 51/54/51 55/58/56 59/62/60 63/67/64 68/71/69; max step 4.78 codes (float) at 14→15, 5 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 26/21/22 30/25/26 34/29/30 37/32/34 42/36/38 46/40/42 50/43/46 54/47/51 58/51/55 63/55/60 67/59/64 72/63/69 76/68/73; max step 4.82 codes (float) at 12→13, 5 (8-bit) at 3→4; monotone yes

### shadows +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 0/0/0 18/18/18 26/26/26 32/32/32 36/36/36 39/39/39 42/42/42 44/44/44 47/47/47 48/48/48 50/50/50 52/52/52 53/53/53; max step 17.75 codes (float) at 0→1, 18 (8-bit) at 0→1; monotone yes; max channel spread 0.00 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 0/18/0 16/27/16 25/32/25 30/36/31 35/40/35 38/42/38 41/45/41 44/47/44 46/49/46 48/50/48 49/52/49 51/54/51 53/55/53; max step 16.21 codes (float) at 0→1, 16 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 30/0/19 35/17/27 38/25/32 41/31/36 44/35/40 46/38/43 48/41/45 50/44/47 52/46/49 53/48/51 55/50/52 56/51/54 58/53/55; max step 16.21 codes (float) at 0→1, 17 (8-bit) at 0→1; monotone yes

### exposure +2, shadows +1

- gray (c,c,c): out 0…12 (R/G/B 8-bit) 43/43/41 49/49/48 54/54/53 57/57/56 61/61/60 64/63/63 66/66/66 69/69/69 71/71/71 73/73/74 75/75/76 77/76/78 78/78/79; max step 6.85 codes (float) at 0→1, 7 (8-bit) at 0→1; monotone yes; max channel spread 2.32 codes
- tint A (c,c+1,c): out 0…12 (R/G/B 8-bit) 43/48/40 49/53/47 53/57/52 56/60/56 60/64/59 62/66/62 65/69/65 67/71/67 69/73/70 71/75/72 73/77/74 75/78/76 76/80/77; max step 6.76 codes (float) at 0→1, 7 (8-bit) at 0→1; monotone yes
- tint B (c+2,c,c+1): out 0…12 (R/G/B 8-bit) 56/44/48 60/50/53 63/54/57 66/57/60 69/60/64 72/63/67 75/65/70 77/68/72 79/70/75 81/72/77 82/73/79 84/75/80 86/76/82; max step 5.70 codes (float) at 0→1, 6 (8-bit) at 0→1; monotone yes

GPU vs Swift mirror, exposure +2, all 75 inputs: max |difference| 0.000 codes (input SIMD3<Int>(24, 25, 24) channel 0: GPU 74.784 vs mirror 74.784)
