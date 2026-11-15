# Granularity and print MTF reference (grain v2)

Numbers read from Kodak's published charts for the grain model (FILM-THEORY §6.2, §6.3):

- `kodak-vision3-250d-5207.granularity.csv`, `kodak-vision3-500t-5219.granularity.csv`: diffuse rms
  granularity σ_D (48 µm aperture) and density per layer on a 0.1 grid of the chart's
  "log relative exposure" (0.0–5.0), with a `flags` column (`layer:flag`, see below).
- `granularity.json`: sources (publication, revision as printed, page, PDF SHA-256, aperture
  statement), per-tick axis residuals, the 18% gray placement `x_gray` with every fit variant,
  `engine_table` (8 shared non-uniform knots in log10 exposure relative to gray, σ_D rows per
  layer, errors; 9- and 10-knot results too), uniform-knot tables under both mappings, σ_D at
  camera stops −4…+4, reading uncertainty, flagged grid points, and the 2383 MTF 50% frequencies.

Offline tool only; nothing here ships.

## Run

```bash
python3 -m venv .venv && .venv/bin/pip install -r Tools/grain-reference/granularity/requirements.txt
.venv/bin/python -I Tools/grain-reference/granularity/digitize_granularity.py \
    --pdf-dir "<folder with the Kodak PDFs>" --out Tools/grain-reference/granularity \
    --overlays "$TMPDIR/granularity-overlays"
```

Needs poppler's `pdfimages`. The PDFs are checked against pinned SHA-256s; output is
byte-identical between runs. Overlays (traced points and grid samples drawn over the chart) go
to a scratch folder only: they contain Kodak's artwork and must not be committed.

## Method

1. The charts are embedded rasters (≈220 ppi), extracted at native resolution with `pdfimages`
   (rendering the page at 600 dpi would only resample the same pixels).
2. Axes are least-squares fits to the detected tick marks: x linear, density linear, σ_D log10
   from the 12 labelled ticks (0.001…0.10); the unlabelled 0.007–0.009 ticks are reported as
   checks. Granularity-chart residuals are ≤ 0.43 px (σ axis ≤ 0.37 px ≈ 0.6% in σ).
3. Each curve is traced column by column inside a corridor around hand-placed guide waypoints
   (in the script, chart units); the guide only picks *which* line, values are darkness-weighted
   pixel-run centres. Solid curves are traced and erased first; dash gaps are bridged linearly.
4. `x_gray` (granularity-chart x of camera stop 0): the sensitometric chart's curves (stop axis,
   log10 2 per stop) are aligned with the granularity chart's own characteristic curves.
   Kodak warns the two charts come from different equipment, and they do differ: every layer of
   both stocks needs the stop spacing compressed to 0.85–0.88 (the granularity chart's curves
   are ~15% steeper) and the 250D blue toe sits 0.16 higher. The primary fit therefore frees a
   horizontal scale and a density offset (all layers, rms 0.016 D); all variants are in the JSON.
5. Mapping (primary = density-matched): chart `x = x_gray + scale·log_e` with the fitted scale
   (0.86 for 250D, 0.87 for 500T). Reason: Kodak's stated reading procedure is by density
   (density → characteristic curve on the granularity chart → σ_D), and the sensitometric chart's
   camera-stop axis is the trustworthy exposure axis; the granularity chart's curves only match
   it with that scale. The density offset of the fit does not enter the x mapping. The
   alternative, `x = x_gray + log_e` (granularity x taken as true log10 exposure), is kept in the
   JSON under `*_alternative_unit_scale`; at camera stops −4…+4 the two differ by up to ~13% in σ_D.
6. `engine_table`: the same 8 log_e knot positions for R, G and B, end knots fixed at −2.4 and
   +2.4 (inside the chart under the primary mapping). The 6 interior positions come from a
   deterministic search (coordinate descent on a 0.01 grid from the uniform layout and 24
   fixed-seed random layouts) minimising the maximum relative error over the three layers of
   piecewise-linear interpolation of σ_D (not log σ) through the trace values, evaluated at the
   0.1-step chart grid points. The 8 values per layer are then re-fitted to minimise the maximum
   relative error (Lawson IRLS, `values_are: minimax_values`), which lowers the max error, so the
   values at the knots are not exactly the trace values there (trace-value results are kept too).
   The search takes about 2 minutes.

## Flags

`on_solid` line hidden under a characteristic curve, value = that curve's centre (± 1 line width);
`shared_with_X` two σ lines print as one (or closer than one line width), same value for both;
`identity_uncertain` two separate lines whose layer cannot be read (250D G/R, x ≤ 1.8; assigned
by keeping G above R as on the labelled right side, swapping changes σ by up to ~13%);
`bridged` gap longer than a dash gap; `crossing` samples dropped where a line crosses;
`edge` the frame hides the line end, value extended linearly.

## Uncertainty

Line half-width ≈ ±1.7% in σ (2 px lines, 140 px per decade); plus the flags above, and `x_gray`
± 0.07 (250D) / ± 0.065 (500T) in log exposure. The 500T sensitometric chart's printed
log-exposure axis is irregular (ticks up to 5.8 px off a straight line); its stop ticks are
regular and are what the fits use.

## Licence note

The values are measurements read from Kodak's charts (H-1-5207, H-1-5219, H-1-2383, © Eastman
Kodak Company). No PDF, chart image or artwork is copied here. Whether the digitized values may
be published under Apache-2.0 is open (MOV-87, MOV-94; see docs/STOCK-DATA.md).
