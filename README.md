# MOV-136 proof provenance — 12 Nov 2026

Source candidate:d4ca216; recovered child98c3d94; main202171f integration2586ef2. This branch holds proof only, separate from feature/main.

- before-iphone.png: child baseline on regular17Pro iOS26.0, main4bec453, before Looks changes; test fixture image behind the medium sheet. before-regular.log.summary.txt records native contrast+clipping failures.
- child-after-iphone260.png: same regular17Pro iOS26.0, child final focused2 pass, recovered UI changes on main4bec453. child-after-iphone.png: child's iOS26.2 final8 pass. These predate later camera/engine integration.
- child-after-duo-current-panel.png: child final7-pass run, current visible Duo panel only. No verified pose transition, folded/unfolded or inner-display proof. The parent later encountered DEVICE_IN_USE twice (one bounded5000ms wait), made no takeover/fold call, and claims no fresh Duo verification.
- integrated-after-iphone.png / integrated-scrolled-iphone.png / integrated-saved-look.png: native test attachments from fresh parent-portrait-regular, iPhone17Pro iOS26.2, source d4ca216 after main202171f integration. All8 library tests pass without skips or failures, including new Looks regressions and edit/compare/rotate/save. No concurrent destination driving occurred in this final run.

## Scope and limits

The regression checks initial contrast+clipping and text clipping after5 scrolls, without an audit issue handler. Broad contrast checks after scrolling still report navigation/viewport-edge text, sometimes unbound; retained failures are not waived. This is not full-app or scrolling-contrast completion; MOV136/MOV59 remain open. Human VoiceOver, physical hardware, true Duo fold/inner and native Mac interaction breadth remain unverified.

Parent reviewed the child source independently, applied the simplify/Swift/bug review workflow, and corrected library test fixture routing and initial orientation. REVIEW.md records ACCEPT/REFUTE evidence. Prior failed parent test bundles remain local with exact logs: camera route assertion (exit65); overlapping proof installation invalidated a run; a missing portrait setup then failed the compact precondition and left fixture skips. Those runs are excluded from positive proof.

Core/Kit macOS/UI tests, strict lint, iOS build and Mac build passed on the integrated branch. Core includes opt-in skipped probes and3 deliberately recorded visual-regression known issues, without unexpected failures. Final native8 pass. iOS Kit native tests also passed; exact count is recorded in the PR.

Local complete evidence (including xcresults and diagnostic failures): /Users/hammad/Documents/Emulsion Review/MOV-136/. Media here contain only simulator test content.
