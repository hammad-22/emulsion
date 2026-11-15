# MOV136 larger text — 15 Nov 2026

Final source717f7f687173c7bbe90aa19af937cc38f064b904 gives recipe text more room by moving Options below it at accessibility sizes. Native toolbar/edge behavior is unchanged; all experimental bar/clip changes were removed.

Before: baseline d916579, native regular iPhone17Pro iOS26.2 AX5 initial Looks attachment (baseline.xcresult). After: adaptive row-only production source, same final production row implementation, native AX5 initial attachment (adaptive.xcresult); that earlier raw audit still failed2 times, so this comparison proves layout only. Later action-fixture changes do not alter production rendering.

regular-saved-ax5.png and duo-current-panel-saved-ax5.png come from final row-only action checks, both platforms default+AX5 pass with no skips/failures. Duo screenshot is its current active panel; no angle/pose was changed or verified. It is not folded/unfolded proof.

Images are copied native attachments without editing. No source math, recipe application, rendering or photo content was changed. Read CHECKS.md and REVIEW.md for failed experiments and limits.
