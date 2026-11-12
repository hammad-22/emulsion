# Metal / Core Image kernels

- `Emulsion.ci.metal` holds Core Image color kernels (`extern "C"`, `coreimage::sample_t`). The Swift mirrors are in `FilmModel.swift`, `FilmModel+Display.swift`, `ColorSpaces.swift`, `Halation.swift` and `Grain.swift`: change both together, using the same names for constants.
- Rebuild with `sh Tools/build-kernels.sh` and commit all three metallibs (macOS, iOS, simulator) together with the source. The deployment target in the script must match `Package.swift`.
- Each kernel gets a comment stating its input and output: scene or display light, working or P3 primaries, premultiplied or not.
- The kernel-argument layout (`kernelArguments`, `misc`/`neg` vectors) is an ABI: when it changes, update the comment block above `filmRender` and the Swift packing together.
- `mirroredEdges` is a warp kernel (edge reflection for halation's blurs) and `gaussianPass` a sampler kernel (exact Gaussian taps for halation's narrow blurs); everything else is a color kernel. `grainNoise` is a generator (no input image, integer pixel coordinates, integer hash: keep it integer-exact so every device draws the same grain, `GrainTests.noiseIsTheSameOnEveryDevice`). Halation's glow (`halationMix`) and the grain noise enter the film kernels as samplers and act on layer exposure and negative density there; a missing one gets a black sampler and k = 0 (or σ·0), which must leave the render bit-identical. With both off the renderer runs `filmSystemPlain` / `filmSystemRelativePlain`, which must stay bit-identical to the full kernels at k = 0 and zero noise.
- Pointwise math belongs in color kernels. Spatial work (blurs, local tone) uses Core Image filters at reduced resolution where it's invisible.
- Watch the per-pixel cost: no new loops or bisection in the live path without measuring.
- Hashes and noise must stay deterministic for a seed and decorrelated across seeds (see the grain tests).
