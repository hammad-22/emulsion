# MOV-147 proof: full-size render corruption

All images come from `iPhone12Pro_ProRAW_CC0.DNG` (raw.pixls.us id 4264, CC0), rendered at the native 3024×4032 with neutral adjustments and downscaled to 1600 px for viewing (JPEG q90, sips). Mac: M4 Max, macOS 27.2.

| File | What it is |
|---|---|
| `before-corrupt-a.jpg` | Old code. A full-size develop rendered by a second `Renderer` after another one had decoded the same file. The lower half is a shifted, magenta copy of the image. |
| `before-corrupt-b.jpg` | Same setup, another run: red fill with a false-colour copy. |
| `before-normal.jpg` | Old code, the render most runs produced (40 of 48). |
| `after.jpg` | With the fix (`Renderer.materialize`, caching context). All 8 renders in that run were identical (4 threads, a fresh `Renderer` each). |

## Numbers (8-bit Display P3 codes, full resolution, 256 px tiles)
| Compared with `after` | Max pixel diff | Mean diff | Tiles with mean diff > 2 | Worst tile |
|---|---:|---:|---:|---:|
| `before-normal` | 1 | 0.017 | 0 of 192 | 0.0 |
| `before-corrupt-a` | 216 | 26.0 | 108 | 97.1 |
| `before-corrupt-b` | 236 | 35.8 | 108 | 102.4 |

The fix gives the old path's uncorrupted image within one code (half-float rounding of the cached intermediate).

Not published here: the 48 MP iPhone 15 Pro Max files that trigger the bug most often (CC-BY-SA, local only). Their numbers are in the PR.
