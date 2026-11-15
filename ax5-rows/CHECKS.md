# Checks — source717f7f687173c7bbe90aa19af937cc38f064b904

Final row-only native action checks: regular iPhone17Pro iOS26.2 default+AX5 both pass, zero skips/failures, exit0 (row-final-regular.xcresult/log). Duo iOS27.2 current panel default+AX5 both pass, zero skips/failures, exit0 (row-final-duo.xcresult/log). Test inputs use fresh isolated bundle com.hammad.emulsion.mov136rowfinal. No fold request was made.

Final UI15 package tests, strict lint/diff checks and Mac app build pass. Current-main Core21 XCTest(3 opt-in skips)+168 Swift Testing(3 known issues) and Kit128 previously passed on same unchanged engine/app-logic source; no new Core/Kit changes.

Unresolved: row-only adaptive raw AX5 audit still2 contrast failures (adaptive.xcresult/log), same count as baseline, not a pass. Baseline diagnostic identifies Quiet Color partly behind toolbar; other finding unbound. Default-size dark regular audit failures were observed in rejected variants; no fresh final row-only default audit pass is claimed. Final-source actual folded/unfolded Duo, full accessibility, human VoiceOver and physical devices remain unverified.

Rejected modifier trials and failed/skipped bundles are retained. See REVIEW.md. No diagnostic filter remains in source.
