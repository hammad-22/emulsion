# MOV-136 review record

Implementation work was performed by this session without child agents. Parent independent source review completed on 12 Nov 2026; publication still depends on the final verification recorded below. No engine/input math, import architecture, camera/stock checkout or new dependency was touched.

## Simplify pass

Reviewed the complete diff against integrated main 4bec453. Kept native List, Section, Button, Menu, ShareLink, fileImporter, alerts and ScrollViewReader. Abandoned the larger scroll-stack rewrite and material/scroll-effect experiments; they did not consistently improve the native audits. The final sectionTitle helper is used for both headings and accepts LocalizedStringKey. Existing MOV-59 fixture helpers and all six existing tests are preserved unchanged. No additional source simplification was justified.

## Swift-review skill

Applied `.agents/skills/swift-review/SKILL.md` after simplify. Scope: LooksButton.swift, LooksPicker.swift, RecipeRow.swift and additive native UI tests. No concurrency, engine, public API, dependencies or action/serialization changes. List rows self-size; semantic primary colors and system font weight adapt to appearance/text size. The explicit heading trait preserves heading navigation after moving text from UIKit section chrome into content. Native sheet/list/glass styling is retained; no opaque replacement, custom blur or row glass was added.

Apple docs checked:
- https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)
- https://developer.apple.com/documentation/swiftui/view/foregroundstyle(_:)
- https://developer.apple.com/documentation/swiftui/view/accessibilityaddtraits(_:)
- https://developer.apple.com/documentation/swiftui/view/bold(_:)
- https://developer.apple.com/documentation/swiftui/section
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/design/human-interface-guidelines/sheets
- https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
- https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)

Availability covers the project's iOS/macOS 26 minimum. `presentationDetents` configures the enclosing sheet; large is the system default. No UIKit/AppKit wrapper or availability fallback was needed.

## Bug review and verdicts

- ACCEPT — The two old unbound contrast identities must not be assumed to be Night Glow. `isolation-duo.log` records actual labels: Everyday summary (“Balanced color with gentle texture.”) and Quiet Color summary (“Restrained color, cool light and fine texture.”). The temporary diagnostic style changed one summary at a time without changing text/layout/action structure; exact diagnostic sources are external. None of its ProcessInfo environment switches or static-button experiments remain in source.
- ACCEPT — Bare List section-header modifiers did not resolve the native clipping warning on regular iPhone. Use self-sizing native content rows with the heading trait (`LooksPicker.swift:68,76,90–94`) and a large native sheet (`LooksButton.swift:15`). Keep header text static/localizable.
- ACCEPT — Broad contrast audits after scrolling can still report text at the navigation/viewport edge, including unbound identities. Retain their unfiltered failing results. The committed regression explicitly checks initial-screen contrast + clipping and subsequent scrolling clipping; this is NOT a full app audit or a scroll-position contrast pass. Do not silently refute or waive those findings.
- REFUTE — Moving headings would remove assistive heading navigation. `sectionTitle` adds `.isHeader`; native description/trait/hit-region checks cover the final picker. Human VoiceOver rotor operation remains unverified.
- REFUTE — The change modifies apply/save/import/share/delete or per-photo grain seeds. Their production closures and RecipeTransfer/RecipeStore/EditSession code are unchanged. Native save/apply/delete regression checks selection, auto-scroll to a saved look and deletion. Kit's `applyingKeepsOriginalAndEachPhotosSeed` and recipe persistence/import tests pass. Files-provider/human/physical-device breadth remains distinct.
- REFUTE — A skipped fixture run is proof. The first stack attempts skipped because diagnostic samples remained. Those bundles are retained and excluded from passing evidence; only final zero-skip runs count. The tests reuse the existing explicit empty-library fixture precondition.

Verdict: source scope is small and Apple-native; exact final checks and outstanding audit/human/device limits are recorded in HANDOFF.md. Parent must independently review this verdict and the evidence.

## Parent integration review — 12 Nov 2026

Reviewed the recovered child source independently against origin/main 202171f after merge2586ef2. Simplify: retained the one shared localizable heading helper; retained native List, Section, sheet, toolbar and actions. Swift review: rechecked Apple presentationDetents/accessibilityAddTraits/performAccessibilityAudit documentation including availability. Native heading traits remain, no overlay or custom material replaces system controls, and shared views compile for Mac. Bug review: production apply/save/delete/import/share closures and render/recipe logic are unchanged. No source correctness finding beyond the test fixture below.

ACCEPT — Camera-first main invalidated older library test launches. Added a common launchLibrary fixture and an assertion that Library appears. With the flag absent, parent-launch-before.xcresult/log records the assertion failure plus the old empty-library skip (exit65). Passing --library in the helper fixes the route for every library test, including both new Looks tests. Existing main walkthrough already used this flag. No camera behavior changed.

ACCEPT — Fresh Duo driving is unavailable: DEVICE_IN_USE names the child's binding; one advised5000ms wait ended with the same error. Did not reuse/close another session or run a project test to override it. Child final-duo evidence is retained, explicitly from the earlier 4bec453-based source and current visible panel. No new pose commands or fold proof.

ACCEPT — Initial contrast+clipping and scrolling clipping are a limited regression scope. Scrolling contrast and full-app findings remain open on MOV136/MOV59; no audit failure is waived or claimed fixed. The passing test has no issue handler. Full human VoiceOver, physical hardware and true Duo inner/fold proof remain unverified.

Verdict: source change is suitable for a scoped draft with its remaining acceptance gates explicit. Final checks/provenance live in HANDOFF.md; do not close MOV136 solely because the scoped PR merges.

ACCEPT — Parent verification interference: during parent-final-regular the parent installed/reopened the same proof bundle on the destination before the native runner had finished. The log then reports lost application connection during the scrolling audit. This run is invalid final evidence and is retained, not counted as a passing result. Re-run from a clean isolated installation with no concurrent GUI/build/install actions on that destination. Do not infer a product crash from that contaminated run.

ACCEPT — Regular-iPhone tests assume the compact portrait layout but did not establish device orientation. parent-clean-regular records the first editor showing Hide Adjustments with the adjustment group/ruler already visible, so tapping Adjust fails; fixture cleanup then leaves samples and later tests skip. EditorContent.swift derives initial visibility from expanded canvas size. Set portrait in the shared launch fixture before app launch; retain this failing run rather than treating skips as proof. This is project test-runner orientation, not a T3 Duo pose command.
