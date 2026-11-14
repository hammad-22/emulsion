# MOV-149 proof: Digicam 2004

Everything here is derived from CC0 material only: the iPhone 12 Pro ProRAW sample (raw.pixls.us id 4264, CC0) and the app's bundled synthetic sample chart. The night and face review scenes are CC-BY-SA and stay local; the real period camera references are look-only and are not published.

- `lake.apple-digicam-strong.jpg`: Apple's render (sips, rotated upright) | Digicam 2004 at its default (Noise 0.6, Processing 0.7) | strong (1.0, 1.0). Each panel 1944 px tall.
- `iPhone12Pro_ProRAW_CC0.digicam.jpg`, `.digicam-strong.jpg`: the full 1944 × 2592 (5 MP, 4:3) exports, `ReviewRenders` with `EMULSION_REVIEW_LOOK`, export intent (camera JPEG round trip, then the review's JPEG 0.95).
- `crop-100pct-*.png`: 100 % crops: branches against white cloud (sharpening halos, violet fringing near clipped light, noise) and dry grass (fringe kept off bright blades).
- `editor-digicam.png`, `editor-film.png`: iPhone 17 Pro Simulator (iOS 26.2), editor Texture group: "Noise"/"Processing" in the digicam process, "Grain"/"Halation" in film; 4:3 crop visible.

Render reliability (MOV-147): every image was rendered in its own process at least twice and taken from the majority byte-identical output, then checked by eye.
