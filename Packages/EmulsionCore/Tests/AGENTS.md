# Tests

- One file per area (film system, tone, color, halation, grain, local tone, pipeline, color spaces). Name tests after the behavior they protect.
- **New tests use Swift Testing** (`@Test`, `#expect`, `@Test(arguments:)` for sweeps). Convert an existing XCTest file when you rewrite it, not piecemeal.
- **Use chromatic inputs, not only gray:** gray hides wrong gamut matrices and channel swaps.
- **Tolerances must match what the docs claim.** If a test needs a looser tolerance, fix the doc too.
- Prefer independent references (published values, colour-science tables) over checking the code against its own mirror.
- Input transforms are checked against `References/input-transforms.json` (and 10-bit video against `References/video-signal.json`) through `ColorReferences` (loaders, tolerances); reuse it for any new input or signal-range test.
- Fixtures are synthetic and deterministic. Never read the user's photo library or private images.
- Timing lives in `PerformanceProbe` and runs only when `EMULSION_PERF=1` is set.
- Suites that read video with AVAssetReader are `.serialized`: its blocking reads starve the Swift concurrency pool when many run in parallel.
