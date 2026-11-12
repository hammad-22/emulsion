# MOV-59 local review — 11 Nov 2026 (America/New_York)

Base: origin/main d07999d. Implementation child worked alone as requested; parent independent review is still required. No push, PR, watch, proof-branch publication or merge performed.

## Simplify pass

Kept production changes to native SwiftUI modifiers: primary/default explanation text, a localized group value, and the picker label's existing capsule as its hit shape. Reused sample-library setup and cleanup in UI tests so the existing fresh-library walkthrough still runs. No import/sample action plumbing, PhotoStore, PhotoImportButton, camera or engine changes. Corrected the touched width comment so it no longer claims every larger-text layout is verified.

## Swift review (project skill)

Read `.agents/skills/swift-review/SKILL.md`, root rules, Apps/iOS, EmulsionUI and EmulsionKit rules. Reviewed the finished three-file diff, strict concurrency/build output, iOS 26 minimum and iOS 27.1 Duo availability exception. No custom glass, color grading, animation, new dependency, actor or public API added. Group title is already localized by AdjustmentGroup. Both regular and current-panel Duo native verification performed; no fold/inner-display claim.

## Findings and verdicts

- **ACCEPT — group value missing (MUST, accessibility).** `AdjustmentPanel.swift:43–44`: label replaced the visible group name without exposing its value. Native baseline regression returned an empty string where Light was expected; final regression checks Light and Color. `before-ruler.xcresult` / `before-ruler.log` are red; final regular and Duo regressions are green.
- **ACCEPT — unselected picker targets only hit their text (MUST, accessibility).** `AdjustmentPanel.swift:62–67`: transparent padding lacked an explicit content shape. Native hitRegion audit flagged Highlights and Shadows before; using the existing capsule for hit testing removes both findings. Same red/green evidence as above. No visual replacement.
- **ACCEPT — empty-library explanation contrast (MUST, accessibility).** `LibraryEmptyState.swift:21`: secondary body text received native “Contrast nearly passed.” `before-explanation.xcresult` independently reproduces the scoped regression red before removing the secondary override. Final regular and Duo explanation-contrast tests pass. Import contrast is outside this change and remains reported for MOV-135.
- **ACCEPT — test fixture isolation (SHOULD, verification).** New tests initially left samples behind, which would make the existing walkthrough skip. Cleanup now removes only the samples these fresh-library tests add; final complete regular suite runs all six tests without skips, including the old edit/save/delete walkthrough.
- **REFUTE — add an explicit selected trait to Looks rows.** Native baseline `testAppliedLookHasSelectedTrait` passed before any RecipeRow change. Final regular and Duo runs also pass on unchanged RecipeRow; extra modifiers would duplicate the system result.

## Bug review

Reviewed state ownership, hit-test geometry, localization, app/test fixture isolation, and scope boundaries. No remaining correctness defect found in the small production diff. The contrast test intentionally targets the explanation only; other contrast issues are handled by its handler and are NOT a full-screen audit pass. Other test names state their categories. Unfiltered audit results are retained separately. No crash retry used; initial failing exits retained.

## Limits / review gates

Parent independent review pending. Full native audit still has unresolved findings; see AUDIT.md. Human VoiceOver adjustable/reset action execution and focus order are not proved by the native audit or drag tests. Regular-iPhone reduced-effects on-state interaction smoke check is recorded; Duo reduced-effects on-state, human motion-sensitivity usability, actual fold transitions/inner-display layouts and physical-device behavior remain gates. The known unfolded sample-title clipping report was not reproduced in the available current panel; that is not a refutation of its original geometry.

Verdict: scoped fixes ready for parent review; MOV-59 acceptance remains open.
