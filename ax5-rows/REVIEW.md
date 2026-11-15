# Independent review and retained trials — MOV-136

Independent simplify/Swift/bug review: adaptive RecipeRow retains the same Apply Button, Applied indicator, accessibility hint, Options label, native Share and conditional Delete actions. AnyLayout changes axis at accessibility sizes without rebuilding children. ACCEPT minor helper-order cleanup, applied.

ACCEPT visual regression in hidden-edge-only trial: despite its raw AX5 contrast/clipping pass, giant row text overlapped the native Looks title at scrolls1 and3. Rejected. Final candidate uses an opaque semantic system navigation background at accessibility sizes, keeps native toolbar controls, and limits edge hiding to iOS where the matching opaque background is applied. Default sizes retain native bar/automatic background visibility and hard edges. Mac edge behavior remains unchanged.

Retained trials (all native, not replacements for final proof):
- baseline d916579: contrast failures after scrolls1 and3; dark regular iPhone26.2. Diagnostic identifies Quiet Color partly behind toolbar; other unbound. No false-positive verdict.
- explicit native toolbar visibility alone: fails.
- List clipped: four contrast failures, rejected.
- adaptive row alone: two contrast failures. Kept for full-width accessibility text, not claimed as contrast fix.
- hidden edge + adaptive: raw AX5 contrast/clipping test passed; save/apply fixture failed offscreen Warm selection/reopen. Visual title overlap rejects this production variant.
- opaque-bar initial attempt: both tests skipped due leftover samples. Not passing evidence.
- opaque-fresh and duo: see final checks once completed.

Temporary diagnostic handler returned false and preserved failures; removed from final source. All failed/skipped result bundles and logs remain in this local artifact directory.

Sources: https://developer.apple.com/documentation/swiftui/anylayout ; https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:) ; https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:) ; https://developer.apple.com/design/human-interface-guidelines/typography ; https://developer.apple.com/design/human-interface-guidelines/scroll-views


## Final scoped decision

All toolbar/background/clip-boundary experiments were rejected and removed. Opaque bar still failed regular contrast; contained collection regressed Duo audits. Final production change is ONLY adaptive RecipeRow, preserving the existing LooksPicker toolbar and edge behavior. This is a readability improvement, not a scrolling contrast fix. Native action fixture now taps visible title text and waits for sheet transitions. Apps/iOS/AGENTS.md records fresh-install acceptance and skip-count rules after repeated invalid skipped runs.
