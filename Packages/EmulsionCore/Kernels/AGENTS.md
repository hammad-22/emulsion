# Metal / Core Image kernels

- Two sources of Core Image color kernels (`extern "C"`, `coreimage::sample_t`), linked into one metallib per platform by `Tools/build-kernels.sh` (`metal-link`, since `metallib -cikernel` takes one input):
  - `Emulsion.ci.metal`, the film process. Swift mirrors: `FilmModel.swift`, `FilmModel+Display.swift` and `ColorSpaces.swift`; loaded by `Kernels`.
  - `Digicam.ci.metal`, the digicam process. Swift mirror: `DigicamModel.swift`; constants arrive as arguments from `DigicamLook`; loaded by `DigicamKernels`. Its `digicamLuma709`, `digicamHash` and value-noise lattice copy `lumaSRGB`, the grain `hash` and `valueNoise` from the film file so its open PRs merge cleanly; share a header later.
  - Function names are global across both files: prefix digicam ones with `digicam`. Change a kernel and its mirror together, using the same names for constants.
- Rebuild with `sh Tools/build-kernels.sh` and commit all three metallibs (macOS, iOS, simulator) together with the source. The deployment target in the script must match `Package.swift`.
- Each kernel gets a comment stating its input and output: scene or display light, working or P3 primaries, premultiplied or not.
- The kernel-argument layout (`kernelArguments`, `misc`/`neg` vectors) is an ABI: when it changes, update the comment block above `filmRender` and the Swift packing together.
- Pointwise math belongs in color kernels. Spatial work (blurs, local tone) uses Core Image filters at reduced resolution where it's invisible.
- Watch the per-pixel cost: no new loops or bisection in the live path without measuring.
- Hashes and noise must stay deterministic for a seed and decorrelated across seeds (see the grain tests).
