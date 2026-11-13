# MOV-146 proof

Tests and tools only; no engine or golden change, so no look change on main.

- `mov25-near-black-ramps.png`: the frozen MOV-25 renders the banding detector reproduces (`References/banding-mov25.json`, #50 at eff715f). Rows: gray ramp, −9-stop floor (banded) / −6 (fixed); blue ramp, −9 / −6. Exposure +2, shadows +1, 24 px per sample. The banded rows jump from black at code 0→1: ΔE00 8.26 (gray) / 8.37 (blue), 4.24× / 4.20× their neighbours; fixed: 2.06 / 3.05, 1.72× / 1.88×. Detector limit: > 1 ΔE00 and > 3.3×.
- `Pixel8Pro_CC0.default.{before,after}.1600.jpg`: `Tools/review-renders.sh` output for #50 (after, eff715f) against main (before, 202171f), downscaled from 8144×6128 for this branch. The full-resolution pairs are local only.
