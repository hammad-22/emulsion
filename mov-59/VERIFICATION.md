# Verification record

All commands ran with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer (Xcode 27.2, 27B52). Workspace: /Users/hammad/.t3/worktrees/emulsion/t3-575ffc0a-5bcb7ac3b93d2bca. No new worktree was made. `git fetch origin main` resolved d07999d; requested issue branch created from the already prepared clean checkout at that commit.

## Passing checks

| Check | Command | Evidence/result |
| --- | --- | --- |
| Core macOS | `swift test --package-path Packages/EmulsionCore` | core.log: 19 XCTest, 1 expected perf skip; 56 Swift Testing tests, 3 deliberately recorded known issues in regression-harness tests; exit 0 |
| Kit macOS | `swift test --package-path Packages/EmulsionKit` | kit-mac.log: 40 tests, exit 0 |
| Kit iOS | from Packages/EmulsionKit: `xcodebuild test -scheme EmulsionKit -destination 'platform=iOS Simulator,id=9AD53177-F6BF-4DC5-AE6D-68D4816996FC' -derivedDataPath /tmp/mov59-kit-build -resultBundlePath /tmp/mov59-proof/kit-ios.xcresult` | kit-ios.log / kit-ios.xcresult: 40 tests, exit 0 |
| UI macOS | `swift test --package-path Packages/EmulsionUI` | ui-mac-final.log: 15 tests, exit 0 |
| Style | `swift format lint --strict --recursive Packages Apps Tools` | lint-final.log empty, exit 0 |
| Whitespace | `git diff --check` | exit 0 |
| iOS build/tests | `xcodebuild test -project Apps/iOS/Emulsion.xcodeproj -scheme Emulsion -destination 'platform=iOS Simulator,id=9AD53177-F6BF-4DC5-AE6D-68D4816996FC' -derivedDataPath /tmp/mov59-build -resultBundlePath /tmp/mov59-proof/final-all-regular.xcresult PRODUCT_BUNDLE_IDENTIFIER=com.hammad.emulsion.mov59proof` | final-all-regular.log / .xcresult: all 6 tests pass, no skips, exit 0; full native original walkthrough included |
| Duo build/tests | `xcodebuild test -project Apps/iOS/Emulsion.xcodeproj -scheme Emulsion -destination 'platform=iOS Simulator,id=9BC93C20-FC11-45B6-85DC-E74E30F5CEF4' -derivedDataPath /tmp/mov59-duo-build -resultBundlePath /tmp/mov59-proof/final-duo-audits.xcresult -skip-testing:EmulsionUITests/LibraryToEditorUITests/testSamplesEditCompareAndSave PRODUCT_BUNDLE_IDENTIFIER=com.hammad.emulsion.mov59proof` | final-duo-audits.log / .xcresult: 5 tests pass, no skips, exit 0; current visible panel only |
| Mac app build | `xcodebuild build -project Apps/macOS/Emulsion.xcodeproj -scheme Emulsion -destination 'platform=macOS' -derivedDataPath /tmp/mov59-mac-build CODE_SIGNING_ALLOWED=NO` | mac-build-final.log: exit 0 |

No engine changes, so no kernel rebuild, color-reference regeneration, golden update or performance run was needed. Package checks were not needlessly repeated after unrelated app-only edits. Shared UI tests and final builds include the final modifiers. The final width-comment cleanup has no executable effect. Native manual proof uses only the bound agent-device commands returned by device_open; snapshots/screenshot inspection are recorded in DEVICE-RECORD.md.

## Deliberately failing checks retained

- before-ruler.xcresult / before-ruler.log: empty group value + Highlights/Shadows hit-region failures, exit 65.
- before-explanation.xcresult / before-explanation.log: explanation contrast failure, exit 65, before removing secondary style.
- before-selection-run.xcresult: broad diagnostic audit before final production fixes, 13 native findings; selection test itself passed. Earlier `before-selection.log` is a compiler failure due to the initially misspelled audit enum `.elementDescription`; corrected to Apple's `.sufficientElementDescription`, not counted as a reproduced app bug.
- final-regular-suite.xcresult: earlier all-suite run passed all other tests / original walkthrough, failed empty contrast for explanation and Import; exit 65. Explanation subsequently fixed with its own failing-before regression.
- full-audit-final.xcresult: final unfiltered audit, 12 findings, exit 65. Exact diagnostic source is full-audit-after.swift; committed source restored afterward. **This is not green and MOV-59 remains open.**

No crash/retry masking. Xcode emits debugger metadata / UIKitToolbar warnings and Duo build-version parsing warnings; test results above remain actual successes/failures. Full-audit source capture and final-regression-tests.swift allow parent review of audit scope.

## Proof handling

proof-media/ contains selected original PNG copies only, with sources.json mapping the source captures/attachments. Media and xcresults are external to the feature branch. Parent must independently review, publish only selected media to proof/mov-59, replace draft proof placeholders with commit-pinned raw URLs, then perform authorized draft publication/CI/readiness. No CI was run here and no remote action was taken.
