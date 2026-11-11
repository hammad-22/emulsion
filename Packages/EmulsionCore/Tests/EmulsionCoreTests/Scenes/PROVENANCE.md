# Frozen real scenes (visual regression, MOV-37)

Developed, downscaled scene-linear images of two public-domain RAW files. The visual regression
suite renders the look on real scene content from these files, so it is insulated from OS RAW
decoder changes and from develop work in flight. The develop step itself is covered by the local
tier (`EMULSION_REFERENCE_SAMPLES`, see `Packages/EmulsionCore/Tests/AGENTS.md`).

Format: half-float RGBA TIFF (LZW, lossless), extended linear sRGB working values, read back
without colour matching. Not OpenEXR: ImageIO's EXR writer changes half floats by a few ulps.

Only CC0 / public-domain sources may be added here. No CC-BY-SA, all-rights-reserved or
"look only" material, ever.

Derivation (both files):

```bash
EMULSION_REGENERATE_SCENES=<folder with the originals> swift test --filter regeneratesFrozenScenes
```

run from `Packages/EmulsionCore`: `Developer.develop(data, maxDimension: 960)`, then
`Renderer.resized` (Lanczos) to a long edge of 240 px with an integral extent, rendered to half
float in the working space. The test prints sizes and SHA-256 of source and output.

| File | Original | Source | Licence | SHA-256 of the original | Derived size | Tests |
| --- | --- | --- | --- | --- | --- | --- |
| `iphone12pro-proraw.tiff` | `iPhone12Pro_ProRAW_CC0.DNG` (29,195,592 bytes) | https://raw.pixls.us, id 4264 | CC0 | `e91e77a4533ed7cce551d83330676ea5c47dd5e55fb38adda7819366afdbdfc2` | 180×240 | Look on Apple ProRAW scene content: default look and a graded edit |
| `pixel8pro-dng.tiff` | `Pixel8Pro_CC0.dng` (45,101,750 bytes) | https://raw.pixls.us, id 7751 | CC0 | `45420c595401547cca950ae58d552bc82b32d31ce1d58c082df33004016197f5` | 240×180 | Look on a non-Apple phone DNG: default look and a graded edit |

Derived file SHA-256 (macOS 27.2.1, Apple M4 Max): `iphone12pro-proraw.tiff`
`8c9e8b0efcb99c420b032d0530f60503f1de02422be79ff50159141b6d78ca43`, `pixel8pro-dng.tiff`
`9a995ca443289e891dadff5257cbcf33c246c977887c5552e6267da448dce91b`.

Notes:

- The frozen files are pixel data only: no EXIF, GPS or maker metadata from the originals is
  carried over (checked with ImageIO: the TIFFs hold only size, depth and compression tags).
- They are whole frames downscaled, not native-resolution crops, so they exercise colour, tone,
  halation and local tone on real content. Real sensor noise and fine detail are averaged away;
  grain is covered by the synthetic cases.
- Core Image ignores the Pixel file's lens-shading map (gain map opcode), so that scene keeps the
  lens vignette. This is fine for a regression fixture and says nothing about develop quality.
