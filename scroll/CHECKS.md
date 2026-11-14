# Scroll-edge checks — source09235c3

- Default iPhone17Pro iOS26.2 before:1 native test,5 contrast failures; diagnostic labels Emulsion on scrolls1–3, unbound4–5. Exit65; before.xcresult/log retained.
- Native hard-edge candidate focused:1 passed with zero failures, exit0; hard-edge.xcresult/log.
- Final source09235c3, no audit handler: full8 library UI tests passed, zero skips/failures,225.472s, exit0. Includes initial and5 scrolled contrast+clipping checks plus save/apply/delete and edit/compare/rotate/save. full-native.xcresult/log.
- UI swift test15 passed; Mac app build passed; strict recursive lint and git diff --check passed. No Core/Kit source changed since prior recorded passing checks.
- Largest accessibility size (AX5) focused2 tests: save/apply/delete passed; Looks contrast/clipping failed once after first scroll, Everyday summary. Exit65; ax5.xcresult/log retained. This is NOT an AX5 full contrast pass.
- AX5 diagnostic repeat retained (ax5-diagnostic.xcresult/log): Everyday summary label bound; frame(32,-217.33,154.67,348.67), list(0,62,402,812), isHittable=true. The frame extends behind navigation. This does not establish a framework bug or justify a waiver. Temporary logging returns false and does not filter errors; absent from final source.

Scoped claim: the5 default-size regular-iPhone scrolling failures are fixed; one largest-size finding remains. Duo current-panel/fold/inner and physical/human requirements remain separately open. No full-app acceptance claim. Native result attachments and all failed bundles are preserved externally.
