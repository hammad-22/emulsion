# Metal / Core Image kernels

- `Emulsion.ci.metal` holds Core Image color kernels (`extern "C"`, `coreimage::sample_t`). The Swift mirrors are in `FilmModel.swift`, `FilmModel+Display.swift`, `ColorSpaces.swift`, `Halation.swift` and `Grain.swift`: change both together, using the same names for constants.
- Rebuild with `sh Tools/build-kernels.sh` and commit all three metallibs (macOS, iOS, simulator) together with the source. The deployment target in the script must match `Package.swift`.
- Each kernel gets a comment stating its input and output: scene or display light, working or P3 primaries, premultiplied or not.
- The kernel-argument layout (`kernelArguments`, `misc`/`neg` vectors) is an ABI: when it changes, update the comment block above `filmRender` and the Swift packing together.
- `mirroredEdges` is a warp kernel (edge reflection for halation's blurs); everything else is a color kernel. `grainNoise` is a generator (no input image, integer pixel coordinates); its noise enters the film kernels as a sampler.
- Pointwise math belongs in color kernels. Spatial work (blurs, local tone) uses Core Image filters at reduced resolution where it's invisible.
- Watch the per-pixel cost: no new loops or bisection in the live path without measuring.
- Hashes and noise must stay deterministic for a seed and decorrelated across seeds (see the grain tests).
