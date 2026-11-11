# Tests

- One file per area (film system, tone, color, halation, grain, local tone, pipeline, color spaces). Name tests after the behavior they protect.
- **New tests use Swift Testing** (`@Test`, `#expect`, `@Test(arguments:)` for sweeps). Convert an existing XCTest file when you rewrite it, not piecemeal.
- **Use chromatic inputs, not only gray:** gray hides wrong gamut matrices and channel swaps.
- **Tolerances must match what the docs claim.** If a test needs a looser tolerance, fix the doc too.
- Prefer independent references (published values, colour-science tables) over checking the code against its own mirror.
- Input transforms are checked against `References/input-transforms.json` (and 10-bit video against `References/video-signal.json`) through `ColorReferences` (loaders, tolerances); reuse it for any new input or signal-range test.
- Fixtures are synthetic and deterministic (the only photos are the frozen CC0 scenes in `Scenes/`). Never read the user's photo library or private images.
- Timing lives in `PerformanceProbe` and runs only when `EMULSION_PERF=1` is set.
- Suites that read video with AVAssetReader are `.serialized`: its blocking reads starve the Swift concurrency pool when many run in parallel.

## Visual regression (MOV-37)
- `VisualRegressionTests.rendersMatchGoldens` renders the fixed cases in `VisualRegressionCases.swift` (wedge, 24-patch chart, P3 primaries, skin-like patches × 7 point edits; halation, local tone, default look and grain scenes; a display-referred chart; two frozen real photos) and compares each with its 16-bit Display P3 PNG in `Goldens/`, per pixel in CIEDE2000 (`ColorDifference`, checked against colour-science and Sharma et al. 2005); `everyGoldenBelongsToACase` fails on a golden no case renders. Harness behaviour (report files, render errors, unreadable goldens) is covered by `VisualRegressionRunTests`.
- One set of thresholds for every case: `VisualRegression.thresholds`, whose doc comment has the measured noise and sensitivity. It detects change; it does not prove the look is right.
- A look change you intend: `EMULSION_UPDATE_GOLDENS=1 swift test --filter VisualRegression` rewrites missing or failing goldens (`=all` rewrites every one). Review the printed summary (`update-summary.md`) and the before/after/diff images in `.build/visual-regression/images/`, commit the goldens in the same PR as the change, and paste the summary into the PR's Proof. Updates fail on CI.
- Frozen scenes in `Scenes/` (see `PROVENANCE.md`) are CC0 only. Never add CC-BY-SA, all-rights-reserved or look-only material. Regenerate them only when the RAW develop changes on purpose (`EMULSION_REGENERATE_SCENES=<folder>`).
- Local tier: `EMULSION_REFERENCE_SAMPLES=<folder>` develops every DNG under it and compares with goldens in `<folder>/emulsion-goldens/`, outside git; same thresholds and update flow. Nothing from it goes into the repo.
- CI uploads the report and every case's images as the `visual-regression-<run>-<attempt>` artifact and adds `report.md` to the job summary.
