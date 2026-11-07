---
name: swift-review
description: Review Swift, SwiftUI and Metal changes in Emulsion against Apple's current guidance and the project's AGENTS.md rules. Use on every PR (after the simplify pass), or when asked to "swift review" a diff, branch or PR.
---

# Swift review (Emulsion)

This reviews **how the code is written**: Apple idioms, our architecture rules, the Duo and iPhone layouts, and engine invariants. It complements the bug review (`/code-review`), which hunts for correctness bugs. Report only real problems, and check each finding before reporting it.

## Scope
Review the PR's diff (`gh pr diff <n>`, or `git diff main...HEAD`). Read `AGENTS.md` and the nested `AGENTS.md` of every folder the diff touches first; they override generic advice. Check the deployment target before advising: iOS and macOS 26 only, Swift 6 language mode.

## Checklist (in order; skip sections the diff doesn't touch)
1. **Engine invariants**
   - Any change to film or input math lands in both the Metal kernel and its Swift mirror, with the same constant names.
   - Metallibs are rebuilt in the same commit.
   - The kernel-argument packing (`FilmModel+Kernel.swift`) matches the comment block in `Emulsion.ci.metal`.
   - No per-pixel loops or bisection added to the live path without a measurement.
   - Spatial effects are resolution-independent.
   - Seeds stay deterministic and independent.
2. **Concurrency** (strict Swift 6)
   - `@Observable` UI models are `@MainActor`; shared mutable state is behind an actor; no GCD, semaphores or completion handlers when async exists.
   - Every `@unchecked Sendable` or `nonisolated(unsafe)` has a comment stating the invariant.
   - Rendering never happens on the main actor.
   - Prefer structured concurrency; flag `Task.detached`.
3. **Swift idiom**
   - Value types and `let`; minimal `public` API.
   - No `try!` or force unwraps except provably constant values.
   - Typed `EmulsionError`; `guard` early exits; modern Foundation (`URL.appending(path:)`, `FormatStyle`, `Date.now`, `count(where:)`).
   - Names follow Apple's API Design Guidelines and the film vocabulary (negative, print, printer lights, stops, log10).
4. **SwiftUI** (app targets)
   - Observation ownership: `@State` owns, `@Environment` / plain properties pass, `@Bindable` only for two-way bindings. No `ObservableObject`, `@Published` or `@StateObject`.
   - Views are small and logic-free; `.task` instead of `onAppear` + `Task`; `NavigationStack` with typed routes; `.foregroundStyle`; no `AnyView`.
   - Don't branch the view tree with `if` where a modifier value would do.
   - Liquid Glass via system APIs (`glassEffect`, `GlassEffectContainer`) and the HIG.
5. **iPhone and iPhone Duo** (equal priority)
   - Each screen has a deliberate unfolded Duo layout, not a stretched phone UI.
   - Reserved regions are respected via `ArrangementView` / adaptive layout (not the hinge angle).
   - State survives fold/unfold.
   - The PR has Simulator proof for the iPhone 17 Pro and Duo, folded and unfolded.
6. **Accessibility and localization**
   - Controls have labels; Dynamic Type works; Reduce Motion and Transparency are respected.
   - User-facing strings are localizable (`String(localized:)`).
7. **Tests**
   - New tests use Swift Testing (`@Test`, `#expect`, parameterized).
   - Chromatic inputs, not just gray.
   - Tolerances match the docs.
   - Bugs come with a regression test.
8. **Hygiene**
   - Minimal comments, which explain why and give the source behind numbers; no stale or narrating comments, no dead code.
   - No GPL code or data; no film brand names in UI strings.
   - `swift format lint` is clean.
   - The PR has a Proof section and no tool-attribution footer.

## Output
- **Findings, most important first.** Give each one:
  - its `file:line`;
  - the rule it breaks (checklist section);
  - why it matters;
  - a concrete before/after fix.
  - Mark each **MUST** (violates AGENTS.md or Apple guidance in a way that matters) or **SHOULD**.
- **Verify before reporting.** Re-read the surrounding code. Where possible, prove the finding: build, run a test, or quote the Apple doc. Drop anything you can't support.
- **Wrap-up.** End with a one-line verdict. Then fix the accepted findings in a follow-up commit or stacked PR, and record ACCEPT/REFUTE per finding in a PR comment.

## Sources this skill draws on (ideas, not copied text)
- Apple: Swift API Design Guidelines, Human Interface Guidelines, and the documentation for Observation, Swift Concurrency, SwiftUI and Core Image.
- Paul Hudson's "SwiftUI Pro" agent skill (MIT, github.com/twostraws/SwiftUI-Agent-Skill).
- Antoine van der Lee's "Swift Concurrency" agent skill (MIT, github.com/AvdLee/Swift-Concurrency-Agent-Skill).
