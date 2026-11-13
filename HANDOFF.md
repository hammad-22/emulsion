# MOV-136 recovery handoff — 12 Nov 2026

Checkout: `/Users/hammad/.t3/worktrees/emulsion/t3-fa933261-bc1d9bcd0039f7fe`
Branch: `hammadshahid22/mov-136-fix-remaining-looks-contrast-and-text`
Recovered source:98c3d94, main202171f integration:2586ef2, library launch fixture:efd9ed9, explicit portrait fixture:d4ca216. Local staged/working recovery patches are preserved in recovery/. No film/input/camera/action/serialization changes.

## Verified source behavior

Uses a large native Looks sheet, primary text for descriptions/empty/load-error text, and self-sizing localizable heading rows with the heading accessibility trait. Native List/Section/ScrollViewReader, system material, toolbar, import, save, apply, delete and share remain. Two native UI regressions cover initial contrast+clipping and scrolling clipping, and save/apply/selection/auto-scroll/delete. All library tests explicitly launch --library on current camera-first main. Parent independent simplify/Swift/bug review and ACCEPT/REFUTE details are in REVIEW.md.

## Evidence and exact scope

- Child failing-before: before-regular.xcresult/log, contrast and text-clipping failures (exit65). Diagnostic identity isolation: isolation-duo.log/attachments, Everyday and Quiet Color summaries. Do not assume Night Glow from older unbound findings.
- Child final-regular262:8 passed, no skips/failures; final-duo:7 passed, no skips/failures, current visible panel only; final-regular260:2 focused tests passed. These were based on main4bec453 with the recovered UI changes, before later camera/engine integration. Provenance is preserved in each log command.
- Parent Core:20 XCTest cases (2 opt-in performance skips), Swift Testing runs88 and127; success, expected real-file/probe skips and3 deliberately recorded visual-regression known issues.
- Parent Kit macOS:96 tests passed; UI:15 tests passed.
- Parent strict recursive swift-format lint and git diff --check passed. iOS app built with the native test runner; Mac app build passed, code signing disabled.
- Parent failing-before library launch: parent-launch-before.xcresult/log, Library assertion failure followed by old fixture skip, exit65. Fixed shared helper uses --library.
- Parent first integrated run: parent-final-regular.xcresult/log INVALID final evidence. A concurrent proof installation/reopen interrupted the target during scrolling; recorded lost app connection,2 fixture skips, exit65. Retained without masking the failure; clean run starts from an uninstalled isolated bundle and no concurrent destination operations.

## Limits and remaining work

Broad contrast audits after scrolling still fail for text near the navigation/viewport edge, including unbound identities; diagnostic failures remain. The committed regression audits initial contrast+clipping and later clipping only, with no issue handler. This is not full scrolling-contrast or full-app completion. MOV136 and MOV59 stay open.

Fresh parent Duo driving returned DEVICE_IN_USE for the child's session, including one5000ms advised wait; stopped without takeover/closure/bypass. No new pose command. Child current-panel proof is not fold/unfold/inner-display proof. Human VoiceOver rotor/use, physical devices, true fold/inner and Mac interaction breadth remain unverified. Parent changed no accessibility device settings. Child settings/lease cleanup was interrupted by usage limit and is not claimed complete.

- Parent next run: parent-clean-regular.xcresult/log failed the compact editor precondition (Adjust absent while Hide Adjustments and rulers were present), then7 tests skipped after the failed cleanup. These are not passing evidence. The shared fixture now establishes portrait before launch; parent-portrait-regular is the final candidate run. All failed results remain.

## Final parent results

Native parent-portrait-regular.xcresult/log passed all8 library UI tests with zero skips/failures (273.580s), including the full edit/compare/rotate/save walkthrough. This run used source d4ca216 and passed with explicit Library/portrait setup; xcodebuild exit0. Source tree is clean. iOS Kit native test run also passed (parent-kit-ios.xcresult/log), xcodebuild exit0. Selected media belong only on proof/mov-136, with commit-pinned links from the draft PR. Parent can merge the scoped reviewed improvement after CI/readiness under the owner's existing authorization; keep unresolved acceptance visible.
