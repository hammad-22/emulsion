# Decisions

## 28 October 2026: positioning and scope (owner)

| Question | Decision |
| --- | --- |
| First customer | **iPhone photographers.** Professional colorists come second, via a **desktop Mac Pro app** on the same engine. |
| Price | **Free** (iPhone and Mac). |
| Engine | **Open source**. Apache-2.0 proposed (permissive, with a patent grant), so no GPL code may enter the engine. Publishing the public repo needs a separate go-ahead (HAM-94). |
| Target devices | **The best current iPhones: iPhone 17 Pro / Pro Max and iPhone Duo.** All performance budgets are set on these; older devices are out of scope for targets. |
| Look names | **Descriptive names only.** No Kodak or Fujifilm names in the app, the store listing or the marketing (HAM-92). |
| Real film test shoot | **Funded** (HAM-89): 250D/500T, ECN-2, scan, optionally a 2383 print. It's the ground truth for every stock model. |
| Milestone order | Accepted from the deep review: M1 correct inputs + iPhone 17 Pro baseline → M2 free stills app on TestFlight → M3 film realism validated against real film → M4 video & interop → M5 Mac Pro app for colorists. |

### Differentiation (draft, to validate in HAM-86 and HAM-20)

> Emulsion is a free, open-source film lab for iPhone: shoot RAW and it develops your photo the way a real negative and print would, with no subscription and no black box, and the same engine colorists can run on a Mac.

The contrast with Dehancer iOS: free versus subscription, open versus closed, and film-lab simulation versus profile presets. The last point needs verifying in the on-device teardown.

### Consequences
- The colorist controls (three-way/CDL, curves, color mixer, scopes, masks) live in the Mac Pro app (M5).
- Apple Log 2 / Apple Wide Gamut and 48 MP ProRAW are first-class inputs (HAM-81, HAM-79).
- Being free removes in-app purchases and subscriptions from scope; sustainability is an open question for later.
- Open-sourcing needs a legal check on publishing digitized datasheet data, plus the patent check (HAM-87, HAM-94).
