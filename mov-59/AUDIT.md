# MOV-59 native accessibility evidence

Date: 11 Nov 2026, America/New_York (tool logs cross into 12 Nov UTC).
Base fetched first: origin/main d07999d (PR32/33 integrated). Branch: hammadshahid22/mov-59-accessibility-voiceover-labels-dynamic. Bundle: com.hammad.emulsion.mov59proof. All app content was bundled synthetic sample data. No film/input math, third-party dependency, import/sample action plumbing, PhotoStore, PhotoImportButton or active camera/stock lane changed.

## What passed

- Native XCUITest regressions on regular iPhone 17 Pro 9AD53177-F6BF-4DC5-AE6D-68D4816996FC, iOS 26.2: **6 tests, zero failures, zero skips** in `final-all-regular.xcresult`. Includes the unchanged full library/edit/compare/reset/rotate/save/delete walkthrough and five accessibility tests.
- Same five accessibility tests on dedicated Duo 9BC93C20-FC11-45B6-85DC-E74E30F5CEF4, iOS 27.2: **5 tests, zero failures, zero skips** in `final-duo-audits.xcresult`. Current visible panel only; no fold command or pose transition was attempted. Original regular-iPhone rotation/export walkthrough was excluded on Duo.
- Library/editor/Looks native audit categories sufficientElementDescription, trait and hitRegion pass. Empty-library textClipped/dynamicType/description/trait (plus initial hitRegion) pass. Group reports Light/Color, ruler label/value are Exposure/0.0 EV and switch to Warmth. Applied Looks selection passes without changing RecipeRow. Existing walkthrough verifies photo selection, edit persistence, pointer drag and reset, comparison and export. These are not VoiceOver gesture tests.
- Explanation contrast regression independently failed before the primary-text change (`before-explanation.xcresult`, exit 65) and passes on both final devices. Its handler deliberately scopes contrast to the explanation; it does not establish a full-screen contrast pass.
- Group value + hit-region regression failed before (empty group value; Highlights/Shadows hit regions, `before-ruler.xcresult`, exit 65) and passes after the two native modifier additions (`after-ruler.xcresult` and final suites).

## Unfiltered final audit: FAILED, 12 findings

`full-audit-final.xcresult` / `full-audit-final.log`, exit **65**. Used the exact final app and a temporary diagnostic variant of the test source (`full-audit-after.swift`) requesting `.all` for initial empty library, populated library, editor and Looks. Final committed regression source was restored byte-for-byte after the run; see `final-regression-tests.swift` (SHA-256 9ace441c0dc79de6e382602e621682a396f26e5c2ef863d9f2df533272adcdeb).

- Empty library: Import label, **Contrast nearly passed** (1). Report to parent/MOV-135; its component implementation was untouched.
- Populated library: Select, **Dynamic Type font sizes are partially unsupported** (1).
- Editor: Shadows, Highlights, Light, Exposure picker, 0.0 EV and Exposure text, **Dynamic Type font sizes are partially unsupported** (6). Their fonts visually scale in the captured large-text layouts, but that observation does not refute the native warnings. Need further investigation/native accessibility usability checks.
- Looks: **Contrast failed** (3) and **Text clipped** (1). Emulsion section heading is bound to one contrast and the clipping report; two contrast elements could not be rebound in the final log. Earlier baseline captured Quiet Color summary / Night Glow contrast warnings. Keep the native screenshots; do not pretend those two final identities are verified.

No hit-region finding or explanation-contrast finding remains in that full final run. Unfiltered audits are diagnostic evidence and are not checked in as permanently failing tests. Focused test category names and the scoped explanation handler make the narrower claims explicit. No failing exit was masked and no crash was retried.

## Dynamic Type / native walkthrough

Bound agent-device drove all manual launches, settings, input and screenshots; device_screenshot was used to inspect both devices. Build/install and native project test runners used Xcode/simctl only as permitted.

- Regular iPhone inspected empty library at accessibility-medium (AX1), accessibility-extra-large (AX3), and accessibility-extra-extra-extra-large (AX5), plus native normal-size library/editor/Looks flow. Final AX5 sample title is fully visible after scrolling. Selected adjustment controls scroll at large sizes; source already has the scroll fallback and ViewThatFits readout.
- Duo current visible panel inspected library/editor/Looks and empty AX5, with final normal-size editor and final AX5 empty screenshots. Do not label these as verified unfolded/inner/closed posture proof: no fresh pose telemetry was obtained. The title is fully visible in this current panel after scrolling. The original report was on unfolded Duo, which was unavailable for this task; it remains unverified there. No speculative layout rewrite was made.
- The body explanation now inherits primary text instead of secondary; glass style, button shape, actions and the aspect-fit photo are unchanged.

## Rulers, motion and human gaps

`AdjustmentRuler.swift:53–60` exposes native adjustable increments/decrements and Reset action; set clamps to the control range. `AdjustmentGroup.swift` defines steps/units; UI tests inspect the label/value and run trait checks. The existing walkthrough executes pointer drag/double-tap reset. Human VoiceOver increment/decrement/custom Reset invocation, focus order, speech clarity, Switch Control, hardware haptics and physical-device visual/performance checks remain **unverified**.

System glass/button/navigation patterns remain; no custom animation or opacity simulation was added. Apple documents automatic Liquid Glass reduced-effects adaptation. Regular iPhone native Settings confirmed Reduce Transparency and Reduce Motion on (value 1), followed by an actual empty-library → samples → editor → Adjust → Looks walkthrough, screenshots and device recording. This is a native settings/interaction smoke check, not a human motion-sensitivity or VoiceOver usability verdict. Duo switch taps read back off, so no Duo on-state was established. See DEVICE-RECORD.md for final restoration and recovery.

## Sources checked before final review

- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
- https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)
- https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityaudittype
- https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityauditissue
- https://developer.apple.com/documentation/swiftui/view/contentshape(_:eofill:)
- https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:)-8esl7
- https://developer.apple.com/videos/play/wwdc2025/219/

Apple explicitly says an audit pass does not guarantee full accessibility; assistive-technology testing is still needed. XCUITest uses the same audit engine as Accessibility Inspector. This task did not operate the Inspector GUI or conduct a human VoiceOver walkthrough.
