# Market desk research (3 Nov 2026)

Stand-in for interviews (MOV-20) and the on-device teardown (MOV-86); Linear MOV-104 and MOV-105. Built from public sources only: no interviews, and no apps were installed. Treat everything here as hypotheses to confirm with real people and real devices.

## Headline
1. **Chromagraph proves the demand, and it's our closest rival.** Announced 28 Oct 2026 (possibly in the App Store from about 20–22 Oct), it went to No. 1 paid in US Photo & Video. It costs $12.99 once, starts from RAW, bypasses Apple's processing and renders Steve Yedlin's signature color, with grading controls (color, exposure, grain, halation). It's stills only.
2. **"iPhone photos look over-processed" is a long-running, mainstream complaint.** Halide built Process Zero around it. Our pitch (RAW in, film out, no Apple look) answers it directly.
3. **The gap is narrower than it looks.** Cheap or free film-simulation apps already exist:
   - Film(ish): free with RAW/ProRAW and print-stock simulation, Pro $19.99.
   - Film Lab 35: free, with a "physically-informed" density/print pipeline.
   - Acetate: free ProRAW with film looks.

   What nobody combines: **fully free + open source + a full negative→print model + video/log + the same engine on Mac with colorist interop.** That combination is our claim, not "the only film lab".
4. **What colorists punish:** halation that's a glow rather than edge-following light, banding and artifacts under stress, and looks that need lots of fixing afterwards.

## Competitors

| App | What it is | Price | Strength | Gap for us |
| --- | --- | --- | --- | --- |
| Chromagraph Camera | RAW stills camera; Yedlin color science replaces iPhone processing | $12.99 once | Credibility, taste, viral launch | One look, closed, no video, no import of existing photos (unconfirmed) |
| Dehancer iOS | Rebuilt for iOS 26 in May 2026; 86 film presets; video timeline; halation, bloom, grain | Paid passes: $150/yr or $9.99/mo; in-app $89.99/yr; photo-only $49.99/yr or $4.99/mo | Breadth, desktop pedigree, 4.3★ (437 ratings) | Paid; RAW still in beta |
| Kino (Lux) | Pro video camera; Apple Log 2 since v1.4; "Instant Grade" presets | $9.99 once | Ease, App of the Year 2024 | Video only; presets, not a film model |
| Halide (Process Zero) | Camera with zero computational processing | Paid/subscription | Owns the "natural iPhone photo" story | No film look |
| VSCO | Social app plus 200+ presets, including film | ~$30–60/yr (from a reseller listing, not VSCO) | Huge audience | Presets on finished JPEGs; not tied to real film |
| RNI Films | Film presets, praised as accurate | Unverified | Accuracy reputation | Presets on finished images |
| Filmbox (Video Village) | Colorists' film emulation plug-in for Resolve/FCP; Photo Mode for Resolve 21 reportedly announced May 2026 (unverified) | 2021 pricing: $129/qtr, $349/yr, $999 perpetual (current price unknown) | Realism praised by colorists | Desktop only, expensive |
| Film(ish) | Film simulation including print stocks; RAW/ProRAW | Free; Pro $19.99 once | Free + RAW + print simulation | Unknown depth; no video/log |
| Film Lab 35 | Film app with a "physically-informed" pipeline (H&D curve, print, halation, grain) | Free (3 stocks); all stocks $4.99 | Cheap, physically-minded | RAW input unclear |
| Acetate | ProRAW camera with film looks | Free | Free + RAW | Looks, not a film model |
| spektrafilm | Free spectral film simulator (darktable, vkdt, Resolve) | Free | Physically based | Desktop, technical |

## What users say (public sources)
- **Real vs fake:**
  - One colorist called a built-in halation tool a "glow", not halation, and said it banded under stress.
  - Other users called some looks "overcooked".
  - Halation should follow bright edges.
  - Grain should vary with density.
- **Filmbox vs Dehancer:** opinions split. Some say Dehancer needs "a lot of tweaking" outside the plug-in, and others name it the best. Filmbox gets credit for being "true film emulation" and for letting you white-balance before or after the emulation.
- **Pipeline:** colorists separate the negative and print stages and want soft highlight roll-off. That matches our engine design.
- **iPhone photographers:**
  - "Over-sharpened, over-processed" is a common complaint.
  - Process Zero users accept noisier, flatter images in exchange for natural ones.
  - Some still prefer the processed look, so it's a matter of taste, not universal.
- **Pricing pain** across photo apps: features locked behind paywalls, surprise charges. Free is a real advantage.

## Ranked needs, and what Emulsion does about them
1. **Natural RAW starting point, no Apple look.** Our RAW path does this; MOV-79 must confirm highlights survive.
2. **One beautiful default that needs no fixing.** It's Chromagraph's lesson, so our default look has to win blind A/B tests (MOV-89, M3).
3. **Believable texture: edge-following halation, density-aware grain, no banding.** Grain and halation v2, plus MOV-99 and MOV-102.
4. **Fast and fluid.** MOV-95 is done; still needs device numbers.
5. **Free, no subscription.** Decided.
6. **Video and log (Apple Log 2).** M4.
7. **Colorist interop: LUT export, timing in printer points.** M4/M5.

## Positioning (draft)
"Chromagraph gives you one cinematographer's film look for $12.99. Emulsion is a free, open-source film lab: RAW in, real negative-and-print simulation out, many looks you can time like a colorist, and the same engine on Mac."

## Gaps and next steps
- Unverified: Chromagraph's import/editing of existing photos; the exact Chromagraph App Store date; how good Film(ish), Film Lab 35 and Acetate really are (add them to MOV-86); Dehancer's RAW quality; current RNI and VSCO prices; Filmbox's 2026 price.
- Real interviews (MOV-20) and the on-device teardown (MOV-86) are still needed, starting with Chromagraph and Dehancer side by side on the same RAW files.

## Sources
- Chromagraph: https://www.newsshooter.com/2026/10/28/chromagraph-camera-ios-app-by-steve-yedlin-asc/ · https://macrumors.com/2026/10/30/rian-johnson-iphone-camera-app/ · https://www.macobserver.com/?p=494827 · https://nofilmschool.com/rian-johnson-steve-yedlin-app
- Dehancer: https://www.dehancer.com/shop/ios · https://blog.dehancer.com/2026/05/04/this-isnt-an-update-its-a-new-app/ · https://apps.apple.com/app/id6443648413 · https://www.dehancer.com/shop/pslr/film/subscribe · https://appshunter.io/ios/app/6443648413/reviews
- Kino: https://www.videomaker.com/news/kino-pro-video-camera-for-iphone-app-now-supports-apple-log-2/ · https://apps.apple.com/us/app/id6472380172
- Halide Process Zero: https://petapixel.com/2024/08/14/halides-anti-intelligent-update-makes-iphone-photos-truly-natural · https://9to5mac.com/2024/08/28/halide-process-zero-feature
- Over-processing complaint: https://forums.macrumors.com/threads/iphone-camera-is-overprocessing-will-it-ever-end.2432274 · https://lenscraft.co.uk/photography-blog/iphone-photo-sharpening-problems/
- Colorists: https://reddit.fsky.io/r/colorists/comments/1h9okxw/dehancernot_for_film_emulation · https://reddit.rtrace.io/r/cinematography/comments/1ctmmeb/does_anyone_use_film_emulation_tools_for_your · https://mixinglight.com/color-grading-tutorials/fpe-part-4-filmbox-ml1143/
- Filmbox: https://www.redsharknews.com/news-roundup-video-village-filmbox-film-emulation-lecia-sl2-s-firmware-update-and-more · https://videovillage.com/blog/
- VSCO / RNI: https://www.directline.pro/service/vsco/ · https://islandinthenet.com/ios-app-review-rni-films/
- Dehancer iOS pricing: https://apps.apple.com/app/id6443648413 (passes, ratings)
- Film(ish), Film Lab 35, Acetate: found by the fact-check review via App Store search; links to add
- App-review pain points: https://bigideasdb.com/state-of-mobile-app-pain-points-2026
