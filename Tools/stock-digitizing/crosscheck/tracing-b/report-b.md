# Tracing B report

Independent second tracing of nine datasheet charts from 600-dpi `pdftoppm` page renders (no embedded images, no other tracing consulted).

## Method

- Each page rendered at 600 dpi; chart cropped by hand-chosen box; all pixel coordinates below are in the crop (crop origin given in page pixels).
- Axis calibration: frame lines and grid lines located as long dark runs; tick marks as short dark runs in a band inside the frame. Anchor values read from the tick labels on the render. Linear least-squares fit per axis; residuals reported.
- Curves: darkness map, grid lines removed (vector charts: thin-run erasure; 2383 raster spectral chart: median-profile subtraction), then an arc-search ridge follower (sample a circular arc ahead of the current point, pick the dark run closest to the current heading, refine perpendicular to it). Near crossings it locks the heading and coasts; at sharp turns it rewinds and accepts the turn. Dashed curves: dash components chained by nearest end ahead, with cubic Hermite bridges over gaps. Near-vertical strokes on the 2383 spectral chart: row-by-row predicted-band tracking. Where a curve was not resolvable (tangential merges), separate pieces were traced and joined with a cubic Hermite bridge using end slopes; these are the 'interpolated spans'.
- Resampled by linear interpolation of the traced centreline on fixed grids (0.05 log E; 5 nm). A grid point is emitted only if it lies inside the traced extent plus a tolerance (3 px; 7 px for the negative dye charts where the 6–8 px frame line covers the curve ends). Within that tolerance the end value is held constant.
- Check: every resampled point re-measured as the centroid of the vertical dark run in its column (`colcheck`); worst offsets listed. Overlays in `overlays/` (trace colour per curve, orange = coasted/bridged, black circles = resampled points); every overlay and zoom was inspected.
- 'Interpolated spans' below list grid points that fall on coasted or bridged segments. Single 5-nm points at grid-line crossings are usually a 1–3 px coast and are not material; multi-point spans are real gaps.

## kodak-vision3-250d-5207 — Sensitometric Curves (page 3)

- Source: 250D p3 render, crop origin (page px) (3000, 4350), size 1700x1650.
- x anchors (crop px -> value): (150, -3.7), (329.5, -3.1), (509, -2.5), (688.5, -1.9), (867.5, -1.3), (1047, -0.7), (1226.5, -0.1), (1405.5, 0.5), (1584.5, 1.1)
- y anchors (crop px -> value): (100, 3.0), (578, 2.0), (1055.5, 1.0), (1533, 0.0)
- Fit: 298.88 px per x unit, 477.65 px per y unit. x residual rms 0.0007 / max 0.0012; y residual rms 0.0003 / max 0.0004 (data units).
- `blue`: grid -3.70 … 1.10; interpolated/coasted grid points [(-3.7, -3.7), (1.1, 1.1)]; worst column re-check offset -0.3 px at -1.65.
- `green`: grid -3.70 … 1.10; interpolated/coasted grid points [(-3.7, -3.7), (1.1, 1.1)]; worst column re-check offset 0.3 px at -2.00.
- `red`: grid -3.70 … 1.10; interpolated/coasted grid points [(-3.7, -3.7), (1.1, 1.1)]; worst column re-check offset 0.2 px at -2.40.
- x calibrated on the top log-exposure ticks only (camera-stops axis ignored). The -3.7 and 1.1 labels sit on the left/right frame lines; interior ticks fit them within 0.0012 log E.
- Curves run frame to frame; the -3.70 and 1.10 points are where the stroke meets the frame line (flagged as coasted, ≤3 px).
- Line width ~7 px vertical (~5.5 px perpendicular) at 600 dpi.
- **Estimated per-point error:** density ±0.003 (≈±1.5 px); log E ±0.004 from calibration plus trace; no crossings or labels on the curves.

## kodak-vision3-500t-5219 — Sensitometric Curves (page 3)

- Source: 500T p3 render, crop origin (page px) (3000, 4250), size 1700x1800.
- x anchors (crop px -> value): (135.5, -4.0), (428.5, -3.0), (712, -2.0), (1005, -1.0), (1330, 0.0), (1616.5, 1.0)
- y anchors (crop px -> value): (177, 3.0), (671.5, 2.0), (1165.5, 1.0), (1658.5, 0.0)
- Fit: 297.32 px per x unit, 493.85 px per y unit. x residual rms 0.0327 / max 0.0502; y residual rms 0.0008 / max 0.0009 (data units).
- `blue`: grid -3.95 … 1.00; interpolated/coasted grid points [(1.0, 1.0)]; worst column re-check offset 0.2 px at -1.15.
- `green`: grid -3.95 … 1.00; interpolated/coasted grid points [(1.0, 1.0)]; worst column re-check offset -0.2 px at -0.90.
- `red`: grid -3.95 … 1.00; interpolated/coasted grid points [(1.0, 1.0)]; worst column re-check offset -0.3 px at -1.10.
- Top 'LOG EXPOSURE (lux-seconds)' ticks are NOT evenly spaced on the render: spacings 293, 283.5, 293, 325, 286.5 px per 1.0 log E. A straight-line fit leaves residuals up to 0.050 log E (per-anchor residuals +0.025, +0.011, -0.036, -0.050, +0.043, +0.007 log E for -4…1; largest at the -1.0 tick, crop x 1005). The bottom camera-stops ticks are uniform at 92.5 px/stop (= 307 px per log E), which also disagrees with the top-axis mean of 297 px per log E. I used the linear fit to all six top anchors (frame -4.0 and 1.0 included). A piecewise fit through each tick would shift values locally by up to ~0.05 log E.
- With the linear fit the left frame (where the curves start) maps to -3.975, so the first grid point is -3.95; -4.00 lies outside the traced extent under this calibration.
- Curves meet the right frame; 1.00 is the frame contact (coasted ≤3 px).
- **Estimated per-point error:** density ±0.003; log E systematic up to ±0.05 because of the uneven top-axis ticks (equivalent to ≈±0.03 D on the straight-line part), random ±0.005.

## kodak-vision3-250d-5207 — Spectral Sensitivity Curves (page 4)

- Source: 250D p4 render, crop origin (page px) (500, 1100), size 1850x1350.
- x anchors (crop px -> value): (260.5, 250), (409.5, 300), (559, 350), (705.5, 400), (854.5, 450), (1004.5, 500), (1153.5, 550), (1302.5, 600), (1449.5, 650), (1598.5, 700), (1747.5, 750)
- y anchors (crop px -> value): (69, 4.0), (350.5, 3.0), (630.5, 2.0), (911.5, 1.0), (1193.5, 0.0)
- Fit: 2.97 px per x unit, 281.00 px per y unit. x residual rms 0.2397 / max 0.4094; y residual rms 0.0016 / max 0.0018 (data units).
- `yellow_forming_layer`: grid 360.00 … 520.00; interpolated/coasted grid points [(490.0, 490.0)]; worst column re-check offset -1.9 px at 360.00.
- `magenta_forming_layer`: grid 400.00 … 600.00; interpolated/coasted grid points [(490.0, 490.0)]; worst column re-check offset 0.8 px at 515.00.
- `cyan_forming_layer`: grid 530.00 … 700.00; interpolated/coasted grid points [(585.0, 585.0)]; worst column re-check offset -0.9 px at 530.00.
- Grid lines at every 50 nm and 1.0 log unit used as anchors; frame = 250/750 nm, 0.0/4.0.
- Curve identity from labels and continuity: yellow 360→peak ~470→falls to ~0.1 at 520; magenta starts at 400 nm (0.62), dips at ~440, peaks at 550, ends at 600; cyan starts at ~530 nm on the bottom (flat foot 530–545), peaks ~655, ends at 700. Yellow/magenta cross at ~490 nm; magenta/cyan cross at ~585 nm (both traced through with heading lock).
- Gap between the end of yellow (520) and the start of cyan (530) is real (not bridged).
- **Estimated per-point error:** ±0.01 log units on gentle parts (281 px/unit, ±2 px); on the near-vertical flanks (yellow 480–520, magenta 580–600, cyan 690–700) a ±1 px x error moves the 5-nm value by up to ±0.05–0.1.

## kodak-vision3-500t-5219 — Spectral Sensitivity Curves (page 4)

- Source: 500T p4 render, crop origin (page px) (450, 900), size 2000x1550.
- x anchors (crop px -> value): (232.5, 250), (402, 300), (572, 350), (741.5, 400), (911.5, 450), (1081.5, 500), (1250.5, 550), (1420.5, 600), (1590.5, 650), (1760.5, 700), (1930, 750)
- y anchors (crop px -> value): (68.5, 4.0), (389, 3.0), (710, 2.0), (1030, 1.0), (1351, 0.0)
- Fit: 3.40 px per x unit, 320.60 px per y unit. x residual rms 0.0622 / max 0.1312; y residual rms 0.0006 / max 0.0009 (data units).
- `yellow_forming_layer`: grid 370.00 … 530.00; interpolated/coasted grid points [(385.0, 385.0)]; worst column re-check offset 1.4 px at 400.00.
- `magenta_forming_layer`: grid 450.00 … 600.00; interpolated/coasted grid points none; worst column re-check offset -0.2 px at 460.00.
- `cyan_forming_layer`: grid 515.00 … 680.00; interpolated/coasted grid points [(590.0, 590.0), (600.0, 600.0)]; worst column re-check offset 0.6 px at 595.00.
- Yellow 370→peak ~400→falls; its lower end lands on the cyan curve's small bump at ~529 nm (T-junction); the last yellow point (530) sits on that junction and is ambiguous by ~0.1.
- Cyan starts at ~510 nm (0.6) with a bump at ~527 and a dip at ~548 before its main rise; I treated the bump/dip as the start of the cyan curve (it is continuous with the cyan rise). This assignment is an interpretation.
- Magenta starts at 450 nm (1.05), peaks at 550, ends at 600 (0.7). Yellow/magenta cross ~500 nm, magenta/cyan ~587 nm.
- Cyan first grid point is 515: the stroke starts at ~511 nm, so 510 falls just outside the traced extent.
- **Estimated per-point error:** ±0.01 on gentle parts (320 px/unit); up to ±0.1 on near-vertical flanks; ±0.1 at yellow 530 (junction).

## kodak-vision3-250d-5207 — Spectral Dye Density Curves (page 4)

- Source: 250D p4 render, crop origin (page px) (2900, 1000), size 1550x1400.
- x anchors (crop px -> value): (192, 400), (507, 500), (822, 600), (1137, 700), (1452, 800)
- y anchors (crop px -> value): (69, 1.8), (195, 1.6), (321, 1.4), (447, 1.2), (573, 1.0), (699, 0.8), (824.5, 0.6), (951, 0.4), (1076, 0.2), (1203.5, 0.0), (1328.5, -0.2)
- Fit: 3.15 px per x unit, 629.82 px per y unit. x residual rms 0.0000 / max 0.0000; y residual rms 0.0006 / max 0.0012 (data units).
- `yellow`: grid 400.00 … 785.00; interpolated/coasted grid points [(540.0, 540.0)]; worst column re-check offset -0.3 px at 555.00.
- `magenta`: grid 400.00 … 800.00; interpolated/coasted grid points [(400.0, 400.0), (460.0, 460.0), (575.0, 575.0), (790.0, 790.0)]; worst column re-check offset -2.6 px at 460.00.
- `cyan`: grid 400.00 … 800.00; interpolated/coasted grid points [(405.0, 405.0), (460.0, 460.0), (540.0, 540.0), (590.0, 590.0), (625.0, 625.0), (750.0, 770.0)]; worst column re-check offset 5.5 px at 405.00.
- `midscale_neutral`: grid 400.00 … 800.00; interpolated/coasted grid points [(625.0, 630.0), (750.0, 770.0)]; worst column re-check offset -1.8 px at 760.00.
- `minimum_density`: grid 400.00 … 790.00; interpolated/coasted grid points [(415.0, 425.0), (435.0, 435.0), (450.0, 450.0), (465.0, 485.0), (495.0, 495.0), (510.0, 510.0), (520.0, 520.0), (540.0, 540.0), (555.0, 555.0), (570.0, 580.0), (590.0, 595.0), (615.0, 615.0), (630.0, 630.0), (645.0, 650.0), (660.0, 665.0), (680.0, 680.0), (695.0, 695.0), (710.0, 710.0), (725.0, 725.0), (740.0, 740.0), (755.0, 755.0), (770.0, 770.0), (785.0, 785.0)]; worst column re-check offset -5.6 px at 485.00.
- Calibration from frame (400/800 nm, 1.8/-0.2) plus ticks every 100 nm and 0.2 D.
- Identities by continuity through crossings: yellow peaks 1.0 at ~445 and its long tail runs at ≈0.00 (min -0.004 near 670) to ~785 nm where the stroke ends; magenta's short-wavelength tail starts ~0.0 at 400, dips to about -0.02 near 445, then rises to the 1.0 peak at ~540; cyan starts at 0.22 at 400, falls to ~0.03 near 500, rises to the 1.0 peak at ~685. So in this tracing the clearly negative dip (-0.02 at 445) belongs to the curve that becomes magenta; the yellow tail is only marginally below zero.
- Midscale neutral vs cyan: they cross at ~630 nm (neutral flat, cyan steep) — neutral is the 0.83-peak curve, cyan the 1.0-peak curve. They converge tangentially and cross again at ~760 nm; 750–770 nm is a Hermite bridge for both. I assumed the steeper cyan ends lower at 800 nm (cyan ≈0.13, neutral ≈0.17); the swap is not resolvable from the pixels.
- Minimum density (dashed) traced by dash chaining; every dash gap (~20 px ≈ 6 nm) is bridged, hence the many single-point interpolated entries. Dashes merged with solid curves at crossings (~420, ~470–485, ~575–595 nm) were not used; those spans are bridges.
- Curves meeting the left/right frame: end values within 7 px of the frame centre are held constant (400 and 800 nm points).
- **Estimated per-point error:** solid curves ±0.004 D (630 px/D, ±2 px), ±0.01 at bridged crossings, ±0.02 for cyan/neutral 750–770 nm and for the identity swap risk at 770–800; minimum density ±0.01 (bridged dash gaps), worst column re-check 5.7 px ≈ 0.009 D at 485 nm.

## kodak-vision3-500t-5219 — Spectral Dye Density Curves (page 4)

- Source: 500T p4 render, crop origin (page px) (3000, 950), size 1650x1600.
- x anchors (crop px -> value): (200, 400), (371.5, 450), (544, 500), (716, 550), (889, 600), (1061.5, 650), (1233, 700), (1406, 750), (1578, 800)
- y anchors (crop px -> value): (54.5, 1.8), (192.5, 1.6), (330, 1.4), (468, 1.2), (605.5, 1.0), (744, 0.8), (881.5, 0.6), (1019.5, 0.4), (1157, 0.2), (1295.5, 0.0), (1433, -0.2)
- Fit: 3.45 px per x unit, 689.30 px per y unit. x residual rms 0.0986 / max 0.1420; y residual rms 0.0003 / max 0.0005 (data units).
- `yellow`: grid 400.00 … 785.00; interpolated/coasted grid points [(415.0, 415.0), (495.0, 495.0), (545.0, 550.0)]; worst column re-check offset 0.4 px at 460.00.
- `magenta`: grid 400.00 … 790.00; interpolated/coasted grid points [(460.0, 460.0), (495.0, 495.0)]; worst column re-check offset -2.1 px at 460.00.
- `cyan`: grid 400.00 … 800.00; interpolated/coasted grid points [(460.0, 460.0), (545.0, 550.0), (640.0, 645.0), (740.0, 770.0)]; worst column re-check offset 1.4 px at 645.00.
- `midscale_neutral`: grid 400.00 … 800.00; interpolated/coasted grid points [(640.0, 650.0), (740.0, 770.0)]; worst column re-check offset 0.5 px at 605.00.
- `minimum_density`: grid 400.00 … 790.00; interpolated/coasted grid points [(410.0, 420.0), (440.0, 440.0), (455.0, 455.0), (465.0, 475.0), (495.0, 495.0), (510.0, 510.0), (525.0, 535.0), (550.0, 550.0), (560.0, 560.0), (570.0, 575.0), (590.0, 595.0), (610.0, 610.0), (625.0, 630.0), (645.0, 645.0), (660.0, 660.0), (675.0, 675.0), (690.0, 690.0), (705.0, 705.0), (730.0, 730.0), (745.0, 745.0), (760.0, 760.0), (775.0, 775.0)]; worst column re-check offset 6.5 px at 420.00.
- Calibration from frame (400/800, 1.8/-0.2) plus ticks every 50 nm and 0.2 D.
- Same structure as 250D: magenta's short tail dips to about -0.04 near 445 nm; yellow tail min ≈ -0.005 near 680.
- Neutral flat segment (~0.81) meets the rising cyan at ~640–650 nm (bridged); neutral is the 0.92-peak curve, cyan the 1.0-peak curve. Cyan and neutral merge tangentially ~740–770 nm (bridged); I assumed cyan ends lower at 800 nm. Not resolvable from pixels.
- Minimum density dashes are short; chained with Hermite bridges; dashes fused with solid curves at crossings were skipped.
- **Estimated per-point error:** solid curves ±0.003 D (689 px/D); ±0.01 at crossings; ±0.02 at 740–800 for cyan/neutral; minimum density ±0.01 (worst column re-check 6.5 px ≈ 0.009 D at 420 nm, a yellow crossing).

## kodak-vision-2383 — Sensitometric Curves (page 4)

- Source: 2383 p4 render, crop origin (page px) (400, 550), size 1800x1850.
- x anchors (crop px -> value): (179.5, -3.0), (435.5, -2.0), (691.5, -1.0), (1203.5, 1.0), (1459.5, 2.0), (1715.5, 3.0)
- y anchors (crop px -> value): (102.5, 6.0), (360.5, 5.0), (614.5, 4.0), (872.5, 3.0), (1128.5, 2.0), (1384.5, 1.0), (1640.5, 0.0)
- Fit: 256.00 px per x unit, 256.29 px per y unit. x residual rms 0.0000 / max 0.0000; y residual rms 0.0027 / max 0.0045 (data units).
- `blue`: grid -1.00 … 1.85; interpolated/coasted grid points [(-1.0, -1.0), (0.35, 0.35), (0.45, 0.55), (0.65, 0.7), (0.95, 0.95), (1.7, 1.7), (1.8, 1.8)]; worst column re-check offset -2.1 px at 1.30.
- `green`: grid -0.70 … 1.85; interpolated/coasted grid points [(-0.7, 0.05), (0.2, 0.2), (0.55, 0.55), (0.7, 0.7), (0.8, 0.85), (0.95, 0.95), (1.25, 1.25), (1.5, 1.5)]; worst column re-check offset 3.0 px at -0.60.
- `red`: grid -0.60 … 2.55; interpolated/coasted grid points [(-0.6, 0.05), (0.4, 0.5), (1.2, 1.2), (1.35, 1.35), (1.55, 1.55), (2.1, 2.25)]; worst column re-check offset -3.0 px at -0.60.
- The chart on the render is an upscaled raster (rows/columns duplicated, ~300 dpi source): edges are stair-stepped by 2–4 px.
- x ticks every 1.0 log E (the 0.0 tick is hidden under the curve toes; not used); y ticks every 1.0 D. Fit residual: x 0, y max 0.0045 D.
- Curve order B, G, R left to right, confirmed by the letters next to the curves.
- Blue starts at log E -1.00 (D≈0.11), exactly where the -1.0 tick mark is; the curve's end mark and the tick coincide.
- Green and red toes overlap into one ~14 px band from about -0.70 to 0.00 (D≈0.03–0.07), lying just above the frame line. In that span green = band top edge + 3 px and red = band bottom edge − 3 px (flagged interpolated). Faint red stroke left of -0.6 not traceable.
- Shoulders: blue and green end where their strokes merge into the common ~4.1 D plateau at log E ≈1.85–1.9 (data stop at 1.85). Red is assigned the plateau line to log E 2.55 (stroke ends ≈2.6). Whether the plateau also belongs to blue/green is not resolvable. Red 2.10–2.25 is a bridge across the merge.
- **Estimated per-point error:** ±0.01 D and ±0.01 log E on resolvable parts (256 px/unit, ±2–3 px stair-steps); on the steep part (gradient up to ~3.5 D per log E) that is up to ±0.03 D at a fixed log E; toes −0.70…0.00 for green/red ±0.02 D; shoulder end points ±0.05 log E.

## kodak-vision-2383 — Spectral Sensitivity Curves (page 5)

- Source: 2383 p5 render, crop origin (page px) (400, 450), size 2000x1400.
- x anchors (crop px -> value): (235.5, 250), (400, 300), (564.5, 350), (726.5, 400), (888.5, 450), (1055.5, 500), (1220, 550), (1384.5, 600), (1546.5, 650), (1711, 700), (1875.5, 750)
- y anchors (crop px -> value): (44.5, 1.0), (356, 0.0), (665, -1.0), (977.5, -2.0), (1286.5, -3.0)
- Fit: 3.28 px per x unit, 310.55 px per y unit. x residual rms 0.3331 / max 0.8522; y residual rms 0.0024 / max 0.0034 (data units).
- `yellow_forming_layer`: grid 365.00 … 510.00; interpolated/coasted grid points [(365.0, 370.0), (400.0, 400.0), (410.0, 415.0), (425.0, 425.0), (450.0, 450.0), (460.0, 460.0), (485.0, 485.0), (495.0, 500.0)]; worst column re-check offset -3.5 px at 365.00.
- `magenta_forming_layer`: grid 450.00 … 585.00; interpolated/coasted grid points [(450.0, 450.0), (475.0, 475.0), (490.0, 490.0), (500.0, 500.0), (545.0, 550.0), (560.0, 565.0)]; worst column re-check offset 2.8 px at 470.00.
- `cyan_forming_layer`: grid 590.00 … 730.00; interpolated/coasted grid points [(600.0, 600.0), (650.0, 650.0), (700.0, 700.0)]; worst column re-check offset -3.4 px at 635.00.
- `magenta_uv_branch`: grid 375.00 … 390.00; interpolated/coasted grid points none; worst column re-check offset -1.8 px at 375.00.
- `cyan_uv_branch`: grid 390.00 … 395.00; interpolated/coasted grid points none; worst column re-check offset n/a.
- Raster chart (upscaled, stair-stepped; grid lines are as dark as the curves, 5–10 px wide). Grid lines removed by subtracting each line's median cross-profile; crossing points lose ~5 px and are coasted.
- x anchors are the 50-nm grid lines; the printed labels are placed unevenly (up to ~6 nm off their grid line) — I trusted the grid lines.
- Yellow-forming: stroke starts at ~362 nm (≈0.0; first grid point 365) → minimum −0.35 at ~400 nm (on the 400 grid line) → peak ~0.62 at ~465 → falls off the bottom at ~511 nm. The steep flank crosses the 500 nm grid line around 490–500 nm; that crossing is bridged (see listed spans).
- Magenta-forming main curve: corner at 450 nm (−1.73) lies on the 450 grid line; one manual control point at that corner (crop px 890, 893). A near-vertical stroke runs from that corner down the 450 grid line to the bottom; I did not encode it (it is at 450 nm only). Peak −0.16 at 550 (on the 550 grid line; tip bridged 545–550). Falls to the bottom at ~585.5 nm.
- Cyan-forming main curve: rises vertically from the bottom at ~589.5 nm to −2.45, then to a peak −1.08 at ~695, falls off the bottom at ~730.
- Two near-vertical strokes at 370–397 nm, both dropping off the bottom. Not labelled. I assigned the left/upper one (starts −0.71 at ~371 nm, reaches the bottom at ~391 nm) to magenta-forming and the right one (from ~389 nm, −1.1, merging into the 400 nm grid line at ≈−2.6 and invisible below) to cyan-forming. This assignment is a guess; it could be the other way, or both could belong to one layer. In the CSV these strokes are written into the magenta (375–390) and cyan (390–395) columns; the main curves start at 450 and 590, so the columns have empty cells in between. The short kink joining them near 383–389 nm, −1.0 is not encoded.
- Magenta's falling flank and cyan's vertical rise touch near 585–590 nm close to the bottom; magenta 585 and cyan 590 lie on near-vertical strokes and are ill-conditioned.
- Near-vertical segments were smoothed in x over ±3 trace points to remove raster stair-steps before resampling.
- **Estimated per-point error:** ±0.01–0.02 log units on gentle parts (310 px/unit, ±3–5 px raster edges); ±0.2–0.5 on near-vertical flanks (yellow 480–510, magenta 575–585, cyan 590 and 720–730, both UV strokes) because a 1 px x error is 0.3 nm and the slope reaches 1 log unit per 3 nm; x calibration residual max 0.85 nm.

## kodak-vision-2383 — Spectral Dye Density Curves (page 5)

- Source: 2383 p5 render, crop origin (page px) (2800, 450), size 1800x1800.
- x anchors (crop px -> value): (219.5, 250), (367.5, 300), (515.5, 350), (665, 400), (813, 450), (962.5, 500), (1112, 550), (1260, 600), (1410, 650), (1557.5, 700), (1707.5, 750)
- y anchors (crop px -> value): (101.5, 1.4), (317, 1.2), (529, 1.0), (741.5, 0.8), (953, 0.6), (1167, 0.4), (1379.5, 0.2), (1591, 0.0)
- Fit: 2.98 px per x unit, 1063.37 px per y unit. x residual rms 0.2000 / max 0.3287; y residual rms 0.0008 / max 0.0015 (data units).
- `yellow`: grid 350.00 … 745.00; interpolated/coasted grid points [(355.0, 355.0), (490.0, 490.0), (530.0, 530.0), (600.0, 600.0), (650.0, 650.0), (670.0, 675.0), (700.0, 700.0)]; worst column re-check offset -0.9 px at 530.00.
- `magenta`: grid 355.00 … 745.00; interpolated/coasted grid points [(490.0, 490.0), (580.0, 580.0), (675.0, 680.0), (695.0, 700.0)]; worst column re-check offset -2.3 px at 680.00.
- `cyan`: grid 350.00 … 745.00; interpolated/coasted grid points [(450.0, 450.0), (530.0, 530.0)]; worst column re-check offset -1.4 px at 530.00.
- `visual_neutral`: grid 355.00 … 745.00; interpolated/coasted grid points none; worst column re-check offset -0.9 px at 380.00.
- Raster chart; axis ticks every 50 nm (250–750) and 0.2 D (0–1.4). Curves start at ~350–351 nm, so 350 is included only where the stroke starts within 3 px.
- Left-end identities: two strokes start near 0.26–0.27 at 350 nm and cross at ~352–355 nm; the one that dips to 0.19 at ~370 and then rises is yellow; the one with the ~0.30 hump at ~387 nm is cyan (it descends to ≈0.03 by 500 nm and continues into the cyan rise). The low curve with the small bump at ~430 nm is magenta's short tail; it turns up into the magenta flank after crossing the cyan hump curve at ~450 nm. Chosen by slope continuity at the ~450 nm crossing; the alternative pairing (hump → magenta) is not excluded by the pixels.
- Magenta's falling flank crosses the rising cyan at ~580 nm; bridged 1185–1215 crop px.
- Yellow and magenta tails converge near 0.00–0.02 D from ~650 to 745 nm and touch; identity there is ambiguous but the values differ by <0.02.
- Cyan and visual neutral stay separate to the right frame (neutral above). The 750 nm column is empty because the 13-px frame line covers the curve ends (last point 745).
- **Estimated per-point error:** ±0.003 D on clean parts (1063 px/D, ±2–3 px raster edges); ±0.01 at crossings; tails 650–745 ±0.01 with possible yellow/magenta swap; left-end values 350–360 ±0.02.

## Overall doubts

- All values are digitised from printed charts; they carry the chart's own drawing errors in addition to the errors above.
- The resampling holds end values constant within the end tolerance (3 px; 7 px on the negative dye charts) instead of extrapolating.
- 500T top-axis tick spacing is uneven; the choice of linear fit vs per-tick fit changes log E by up to 0.05.
- Curve-identity choices made by continuity (not by label) are listed per chart: 250D/500T dye cyan vs neutral after ~750 nm; 500T spectral-sensitivity cyan bump/dip near 510–550 nm; 2383 spectral-sensitivity UV strokes; 2383 dye hump curve (cyan) vs bump curve (magenta).
