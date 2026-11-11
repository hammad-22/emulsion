# Decisions

## 10 November 2026: minimal glass editing (owner)

The owner chose an ultra-minimal editor with an immersive photo, generous native Apple Liquid Glass and controls revealed on demand. Use Photos-style adjustment rulers: one active adjustment, a horizontal tick-mark scale, fixed indicator, value readout and neutral detent. Ordinary stacked sliders are not the final design. Keep full-image aspect fitting and a neutral surround for judging the edit; do not add an ambient blurred-photo background. Rulers must support accessible increments and reset, and retain the selected control and edit through hiding and rotation. Look recipes remain MOV-65. Duo uses its own expanded composition and reserved-region APIs; show regular, folded and unfolded concepts to the owner before implementing that layout (MOV-119).

## 7 November 2026: native visual quality (owner)

The working prototype is not the final visual design. The iOS app should be beautiful and unmistakably native, with more transparency and Liquid Glass, while feeling fast and lightweight. MOV-54 owns the reusable visual system; MOV-55, MOV-56 and MOV-119 apply it to the library, editor and Duo layouts. Keep the photograph central and its color trustworthy, use system typography and controls, and avoid redundant effects or continuous decorative animation. Accessibility and measured device performance remain acceptance criteria.

## 28 October 2026: positioning and scope (owner)

| Question | Decision |
| --- | --- |
| First customer | **iPhone photographers.** Professional colorists come second, via a **desktop Mac Pro app** on the same engine. |
| Price | **Free** (iPhone and Mac). |
| Engine | **Open source**. Apache-2.0 proposed (permissive, with a patent grant), so no GPL code may enter the engine. Publishing the public repo needs a separate go-ahead (MOV-94). |
| Target devices | **The best current iPhones: iPhone 17 Pro / Pro Max and iPhone Duo.** All performance budgets are set on these; older devices are out of scope for targets. |
| Look names | **Descriptive names only.** No Kodak or Fujifilm names in the app, the store listing or the marketing (MOV-92). |
| Real film test shoot | **Funded** (MOV-89): 250D/500T, ECN-2, scan, optionally a 2383 print. It's the ground truth for every stock model. |
| Milestone order | Accepted from the deep review: M1 correct inputs + iPhone 17 Pro baseline → M2 free stills app on TestFlight → M3 film realism validated against real film → M4 video & interop → M5 Mac Pro app for colorists. |

### Differentiation (draft, to validate in MOV-86 and MOV-20)

> Emulsion is a free, open-source film lab for iPhone: shoot RAW and it develops your photo the way a real negative and print would, with no subscription and no black box, and the same engine colorists can run on a Mac.

The contrast with Dehancer iOS: free versus subscription, open versus closed, and film-lab simulation versus profile presets. The last point needs verifying in the on-device teardown.

### Consequences
- The colorist controls (three-way/CDL, curves, color mixer, scopes, masks) live in the Mac Pro app (M5).
- Apple Log 2 / Apple Wide Gamut and 48 MP ProRAW are first-class inputs (MOV-81, MOV-79).
- Being free removes in-app purchases and subscriptions from scope; sustainability is an open question for later.
- Open-sourcing needs a legal check on publishing digitized datasheet data, plus the patent check (MOV-87, MOV-94).

## 6 November 2026: product shape (owner)

| Question | Decision |
| --- | --- |
| iOS apps | **One app.** It opens straight to the camera, with instant capture from the Lock Screen and Camera Control (MOV-122). The editor is one swipe away and simple by default. |
| Capture | **Always RAW**, with a chosen **recipe** (named look, like Fujifilm film recipes) applied non-destructively on top and shown live in the viewfinder (MOV-121, MOV-65). |
| Mac app | Aperture/Lightroom-class pro app on the same engine; the iOS app is the simpler, cleaner version (MOV-120). |
| iPhone Duo | Equal priority with regular iPhones; unfolded layouts use the whole landscape canvas (MOV-119). |
| Repo layout | One monorepo: `Packages/` (EmulsionCore engine, EmulsionKit, EmulsionUI), `Apps/` (iOS, macOS), `Tools/`, `docs/`. Revisit as it grows (MOV-120). |
| Agent rules | `AGENTS.md` is the single source for Codex and Claude; Linear issues are living documents with a "For agents" section. |

## 10 Nov 2026 — Duo layouts retain the iOS 26 minimum (MOV-62/119/63)

Under the owner's delegated continuation, use an immersive aspect-fit photo on a neutral surround. On expanded canvases the editor shows every adjustment group in a persistent side inspector by default, dismissible with Adjust (an explicit choice survives folding); compact canvases keep the single ruler revealed by Adjust. The expanded library is a four-column grid beside a preview pane (photo, date, RAW/Edited) with an explicit Edit action, in the system appearance. Camera and Look recipes remain separate work.

The Xcode 27.2 SDK declares ArrangementView, ReservedRegion, split layout sizing and toolbar axis behavior available from 27.1. Keep the iOS 26 deployment minimum and ordinary-iPhone layout behind justified availability guards, an exception to the general no-back-deployment-fallback rule. Use size classes and reserved regions, never model-name/size detection or hinge angles. Keep edit sessions, group/ruler selection and library preview selection above layout branches. Native folded/unfolded proof is required before calling MOV-62/63 acceptance complete.

Sources: [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview), [ReservedRegion](https://developer.apple.com/documentation/swiftui/reservedregion), [adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/), [system vertical bars](https://developer.apple.com/videos/play/tech-talks/111462/). Checked against installed arm64 Simulator and device Swift interfaces, Xcode 27.2 (27B52).
