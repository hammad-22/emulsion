# Stock digitizing

Turns the characteristic-curve, spectral-sensitivity and spectral-dye-density charts in the
publisher's film datasheets into fixed-grid CSVs with a provenance manifest per stock. Offline
helper, never shipped.

The CSVs are not published in this repository (`docs/DECISIONS.md`, 12 Nov 2026): write them to the
local reference-data folder outside git, `EMULSION_REFERENCE_DATA` or else
`~/Documents/Emulsion Research/datasheet-tracings`. Only the manifests are
committed, in `Packages/EmulsionCore/Sources/EmulsionFit/Resources/StockData/<stock>/`; each pins
its CSVs by SHA-256, and the Swift loader refuses a CSV that doesn't match.

## Run

Needs Python 3, poppler (`pdfimages`, `pdftotext`) and the source PDFs (not in the repo; URLs and
SHA-256 in `charts.json` and each `manifest.json`).

```bash
python3 -m venv /tmp/digitize-venv
/tmp/digitize-venv/bin/pip install -r Tools/stock-digitizing/requirements.txt
/tmp/digitize-venv/bin/python -I Tools/stock-digitizing/digitize.py \
    --pdf-dir <folder with the PDFs> \
    --out ~/"Documents/Emulsion Research/datasheet-tracings" \
    --manifests Packages/EmulsionCore/Sources/EmulsionFit/Resources/StockData \
    --overlays <scratch dir> --traces <scratch dir>     # optional, for checking
```

The tool checks each PDF's SHA-256 and printed revision, extracts the embedded chart images with
`pdfimages -png` (native pixels), and writes byte-identical output on every run: CSVs and manifests
to `--out/<stock>/`, and with `--manifests` each manifest also to `<manifests>/<stock>/`. `imageSHA256`
in the manifests is of the PNG written by poppler 26.08.0; another poppler may encode it differently. `--overlays`
writes each chart at 3x with the traced centreline (curve colour = measured, orange =
interpolated) and the resampled grid values (circles); look at them after any config change.
`--traces` writes the raw per-pixel traces. `--only <stock id>` limits a run to one stock. Each stock in `charts.json` states its `filmType`
(`cameraNegative` or `printFilm`), copied to the manifest with each chart's `gridStep`.

## Cross-check and proof plots

An independent second tracing of the same nine charts (tracing B) is kept locally, by default in
`<reference data>/crosscheck/tracing-b/`; only its `report-b.md` is in `crosscheck/tracing-b/` here. It was made separately: 600-dpi `pdftoppm` page renders instead
of the embedded images, its own axis calibration, and an arc-search ridge follower. It is used only
as a cross-check, never as data.

```bash
venv/bin/python -I Tools/stock-digitizing/compare_tracings.py [--data <dir>] [--tracing-b <dir>]   # writes crosscheck/agreement.md
venv/bin/python -I Tools/stock-digitizing/plot_curves.py --out <scratch dir> [--data <dir>] [--tracing-b <dir>] [--fit-dir <dir>]
```

`compare_tracings.py` reports, per curve, n, RMS, mean and max |A - B| over the common grid points,
and for characteristic curves the difference along log E (|dD| / slope, where the slope exceeds
0.2 D per log E). It exits non-zero if a characteristic curve differs by more than 0.03 D or
0.02 log E (MOV-16) at points tracing A traced itself (outside its interpolated and shared spans).
`plot_curves.py` draws both tracings and their difference on plain axes (no chart artwork, which
is the publisher's copyright), and, with `--fit-dir`, each camera negative's characteristic curves
(`filmType` in the manifest) against `<id>.negative-fit.csv`. Both scripts find the stocks, chart
files and grid steps in the StockData manifests, read tracing A from the reference data (`--data`,
else `EMULSION_REFERENCE_DATA`, else the default folder), and stop if its CSVs are not the ones the
manifests pin. Its PNGs are proof material, not repo content.

## Method

- **Axes.** Frame lines and every labelled tick or grid line are found on a strip just inside the
  frame, keeping only features that cross the whole strip; centroids are sub-pixel. A linear fit
  over all measurable ticks maps pixels to data; per-tick residuals go in the manifest.
- **Curves.** A line follower walks each curve a pixel at a time and takes the darkness-weighted
  centre of the line on a profile perpendicular to its local direction, so steep flanks are
  sampled along the curve rather than per column. `charts.json` lists, per chart, seed points and
  waypoints (the trace must pass within 3 px of each, which catches a swap at a crossing), text
  boxes to ignore, and which curves leave the plot and come back (`pieces`).
- **Merged stretches.** Where a curve lies on the axis line it is read from the stroke's visible
  upper or lower edge, plus or minus half the line width. A line several curves share (2383 toes,
  shoulders and dye tails) is given to each and listed in `sharedSpans`.
- **Hidden stretches.** Frame, ticks and listed text boxes are unknown; grid lines are blank. The
  trace coasts across crossings, grid lines and dash gaps; each coasted stretch is replaced by PCHIP
  interpolation between measured neighbours and listed in `interpolatedSpans` when longer than 4 px
  (10 px for the dashed curve). A sharp peak hidden in a grid line is rebuilt from its two arms and
  the ink at its tip. Curve ends hidden by the frame line are continued straight to it.
- **Resampling.** Measured points get a 5-tap binomial filter (sigma 1 px). The centreline is
  resampled to log E steps of 0.05 or 5 nm steps by linear interpolation between neighbouring trace
  points (about 1 px apart), only inside each curve's drawn extent; a grid point up to 0.5 px past
  a curve end takes the end value. Empty cell = not drawn (or not separable; see the notes).
- **Uncertainty.** Per point, 1 sigma = half the drawn line width plus the axis's largest tick-fit
  residual, in data units, with the steep-flank y figure in the note. It does not cover how
  accurately the publisher drew the chart.

## Limits

Charts are small rasters (64-226 px per axis unit). Where curves run together (toes, shoulders,
tangent crossings, tails on the baseline) or under ticks and grid lines, values are interpolated
or left out; every case is in that chart's `notes`. Two short unlabelled curves on the print-film
spectral-sensitivity chart are assigned to layers by guess (see its notes). No smoothing or model
fitting beyond the above; these are traced charts, not measurements of film.
