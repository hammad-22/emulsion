# MOV-147 (reopened): proof images

Both images come from the CC0 iPhone 12 Pro ProRAW sample (raw.pixls.us id 4264) and Apple's decoder alone
(`Tools/raw-contrast-zero-repro.swift`), no Emulsion code.

- `apple-decode-reference-vs-corrupt-cc0.jpg`: left, the decode rendered through a caching context; right, one of the
  corrupt renders at `contrastAmount` 0 and `localToneMapAmount` 0 through a context that doesn't cache intermediates
  (18 of 48 renders were corrupt; 0 of 24 at contrast 1e-4). Quarter size.
- `contrast-0-vs-1e-4-crop-200pct.png`: a 400 px crop at 200 %: contrast 0, contrast 1e-4, and their difference ×16
  around mid-gray. Whole frame, 8-bit Display P3: mean 0.24 codes, max 6, 1.6 % of pixels over one code.
