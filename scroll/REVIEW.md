# Scroll contrast continuation review — 12 Nov 2026

Scope: d4ca216..09235c3, two lines. LooksPicker adds native .scrollEdgeEffectStyle(.hard, for:.all), and the existing regression now audits contrast plus clipping after all5 scrolls. There is no issue handler or ignored finding in final source.

## Evidence and verdicts

ACCEPT — Strengthening the audit on prior d4ca216 source reproduces5 contrast failures (before.log/before.xcresult, exit65): Emulsion heading for scrolls1–3, unbound for4–5. The previous clipped-only scroll check did not establish contrast. Temporary identity logging returned false and did not waive failures; it is absent from09235c3.

ACCEPT — Hard edges on all edges pass the same focused audit at default iPhone17Pro26.2 text size, zero failures (hard-edge.xcresult/log, exit0). Earlier child experiments applied hard/hidden only at the bottom and changed other heading/material variables; those are distinct from this all-edge test. No assumption of equivalence or deletion of their failed results.

Independent read-only agent completed simplify → swift-review → bug review of09235c3. No substantive findings. It independently confirmed Apple26+ availability and the documented hard/all example, and verified baseline5 vs candidate0 from logs. Review did not run builds/devices or establish Duo posture, hardware/human or final MOV140-integrated behavior.

ACCEPT — The system edge boundary appearance changes on both supported shared-view platforms. Do not describe this as no visual/material change. No custom material, layout/state/photo/render/action change was made.

Apple references checked:
https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)
https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/hard
https://developer.apple.com/design/human-interface-guidelines/materials

Final full native and largest-size results are in CHECKS.md. Native/visual proof covers only explicitly recorded devices/settings. Duo verified fold/inner, human VoiceOver and hardware remain open; no failed result is waived.
