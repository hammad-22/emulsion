# Emulsion

A free, open-source film lab for iPhone (Mac later): RAW and log footage in, a simulated negative → print film process out. **The engine is the product**: fast, honest about what it models, and verified.

- Background: `docs/ENGINE.md` (how it works), `docs/DECISIONS.md` (owner decisions), `docs/RESEARCH.md`, `docs/MARKET-RESEARCH.md`.
- Work: Linear team **Emulsion** (key `MOV`). GitHub: `hammad-22/emulsion` (open source, Apache-2.0).
- This file is the single source of rules for every coding agent (Codex reads it directly; `CLAUDE.md` imports it). Folder-specific rules live in nested `AGENTS.md` files: `Packages/EmulsionCore/Kernels/`, `Packages/EmulsionCore/Tests/`, `Apps/iOS/`. Read the nested file before editing in that folder.

## Stack
iOS 26 / macOS 26 only, iPhone 17 Pro and iPhone Duo as targets. Swift 6.4 toolchain, SwiftUI with Liquid Glass, Core Image color kernels compiled to Metal libraries, SwiftPM. No third-party dependencies yet; any new one needs a reason and a license check.

## Layout
- `Packages/EmulsionCore/`: the engine package. Every look decision lives here.
  - `Sources/EmulsionCore/`: film math (`FilmModel`), input transforms (`ColorSpaces`), develop (`Developer`), render graph and export (`Renderer`), stock and texture constants (`FilmLook`), kernel argument packing (`FilmModel+Kernel`).
  - `Kernels/Emulsion.ci.metal`: GPU kernels; must match the Swift mirror. Compiled `.metallib`s are checked in under `Resources/Kernels/`.
  - `Sources/EmulsionFixtures/`: synthetic test images. `Tests/`: the test suite.
- `Apps/iOS/`: the iOS app (`Emulsion.xcodeproj`, sources in `Emulsion/`). Only the data layer exists; the camera and screens aren't written, so it doesn't compile yet (MOV-96).
- `Tools/`: `build-kernels.sh` rebuilds the metallibs.

## Commands
Run these yourself to verify every change. A change isn't done until they pass.
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sh Tools/build-kernels.sh                                    # after any .metal change
(cd Packages/EmulsionCore && swift test)                     # must stay green
(cd Packages/EmulsionCore && EMULSION_PERF=1 swift test --filter PerformanceProbe)  # Mac timings
swift format lint --recursive Packages Apps                  # style (config: .swift-format)
```

## The Apple way
- **Apple's documentation is the reference.** Before using an API, check its current page on developer.apple.com (availability, deprecations, recommended replacement). Follow the Human Interface Guidelines for UI, and Apple's sample code and WWDC guidance for patterns.
- **Apple frameworks first:**
  - SwiftUI, Observation, Swift Concurrency, Swift Testing, SwiftPM;
  - Core Image and Metal for imaging; AVFoundation for capture and video; PhotoKit for the library;
  - `swift format` for style.
  Use a third-party library only when Apple has no equivalent, and note why.
- **Use the newest platform APIs**, since we only support iOS/macOS 26: Liquid Glass materials, Swift 6 language mode, `@Observable`, Swift Testing. Don't write back-deployment fallbacks.
- **Follow Apple's API Design Guidelines** for naming (swift.org/documentation/api-design-guidelines).

## Workflow
- **Branch per topic, PR into `main`.** Never commit to `main`. Ask before pushing to a new remote or making anything public.
- **Stack dependent PRs with GitHub stacked PRs** (`gh stack`, needs gh ≥ 2.90 and `gh extension install github/gh-stack`):
  - `gh stack init <branch>` to start; `gh stack add <branch>` for each dependent change; `gh stack submit` to push and open the PRs; `gh stack sync` after merges.
  - GitHub rebases the rest of the stack when a lower PR merges, so don't rebase by hand.
  - Edit each PR description after `submit` to use the template.
- **Reproduce bugs with a failing test first, then fix.**
- **Review agents always.** Have an independent agent check any non-trivial engine change, research claim or verdict. Back claims with proof (file:line, a reproduced number, a source URL) and say what's unverified.
- **Reuse before writing.** Search for an existing helper before adding one. Duplicates between Swift and Metal are deliberate mirrors; any other duplicate is a bug.
- **Leave it cleaner.** Fix stale comments and dead code in the files you touch.
- **Prove it in the PR.** Every PR has a **Proof** section (template in `.github/pull_request_template.md`):
  - UI changes: before/after screenshots or a short screen recording from the iOS Simulator (`xcrun simctl io booted screenshot|recordVideo`), and from a device when it matters;
  - engine changes: before/after renders of a reference fixture, plus the measured numbers;
  - docs-only changes: say "no visual change".
- **Run the app in the Simulator** for any app change; don't stop at "it compiles". Use the iPhone 17 Pro simulator, plus iPhone Duo once the Xcode 27.1 SDK is installed.
- **PR descriptions** cover what, why, proof, testing and the Linear issue. No tool-attribution footers.
- **Review before the PR, then open it as a draft:**
  1. On the finished branch, run a simplify pass (`/simplify` in Claude Code) and apply the fixes.
  2. Run the Swift review skill (`.agents/skills/swift-review/SKILL.md`; `/swift-review` in Claude Code).
  3. Run a bug review: `/code-review high` on the branch diff (or Codex's code review). For risky engine or color-pipeline changes, note in the PR that `/code-review ultra` is recommended; only the owner can launch it.
  4. Investigate every finding and mark it ACCEPT or REFUTE, with proof (a reproduction, file:line or a test). Fix what's accepted, adding a regression test for each real bug.
  5. Open the PR as a **draft** (`gh pr create --draft`, or `gh stack submit --draft`) with the verdicts in a PR comment.
  6. Mark it ready (`gh pr ready`) once CI is green.
- **Merging:** the parent session merges ready PRs once CI is green and the review verdicts are recorded. Stacks merge bottom-up.

## Sessions and project memory
- **The project's memory lives in Linear**, not in any chat. Start every session by reading the *Emulsion V0 — State & handoff (read first)* document on the **Emulsion V0** initiative, then this file, then your issue.
- **One session per Linear issue.** A parent session plans the work and starts one child session (Claude or Codex) per issue, on the issue's Linear branch name.
- **Before ending a session:**
  - update the issue description (plan, findings, decisions, PR links);
  - add a dated line to the state document's Log;
  - refresh its Status section if anything changed.
  - Decisions made in conversation go into the state document or `docs/DECISIONS.md` the same day.

## Linear
- **Projects:**
  - *Emulsion Engine*: milestones E1 inputs, E2 film realism, E3 video/HDR/interop, E4 Windows (later).
  - *Emulsion iOS App*: I1 builds and runs, I2 stills on TestFlight, I3 video.
  - *Emulsion Mac App*: X1 MVP, X2 colorist tools, X3 plugins.
  - *Emulsion Product & Launch*: P1 demand, P2 open source and legal, P3 App Store.
- **Labels:** one *Platform* label (iOS, macOS, Engine, Windows) plus one *Area* label (Color I/O, Texture, and so on).
- **Issues are living documents.** Each has a "For agents" section: where to start, how to verify, what needs the owner.
  - When you learn something or find a better approach, rewrite the plan in the description and say why in a comment.
  - Link PRs, and move the status as work progresses.
  - New issues follow the same shape: what/why, acceptance, For agents.
- **Branch names** use Linear's suggestion (e.g. `hammadshahid22/mov-96-...`) so PRs link to their issue automatically.

## Hard rules
- Film/input math changes go into the Metal kernel *and* its Swift mirror, with metallibs rebuilt in the same commit.
- Don't call anything "physical", "accurate" or "like stock X" without a measurement or a primary source. Label artistic choices as artistic.
- No GPL code or data in the engine or apps (Apache-2.0 plan, MOV-94). No film brand names in the product (MOV-92).
- Don't add per-pixel iterative solves to the live preview path without profiling on device.

## Keep this file current
Update this file, or the matching nested `AGENTS.md`, in the same change when:
- a convention, command or the layout changes;
- an owner decision lands;
- the same mistake happens twice.

Keep it under 200 lines: specific, true, no duplicates. Delete rules that no longer apply.

## Swift

- **Modern Swift only.** Use async/await and structured concurrency (`async let`, task groups), not completion handlers, GCD or semaphores. Use `Task.sleep(for:)`.
- **Concurrency.** Code must compile cleanly under strict concurrency. Never silence a warning by downgrading checks. Every `@unchecked Sendable` or `nonisolated(unsafe)` needs a comment saying why it's safe.
- **Types.** Structs, enums and `let` by default; use a class only when reference semantics are needed. Prefer immutable configuration (film stocks) over public mutable vars.
- **Access control.** Make things `private` or internal unless the app needs them. The public API of `EmulsionCore` is a product surface: keep it small.
- **Errors.** Use the typed `EmulsionError` (`LocalizedError`). No `try!`, and no force unwraps except provably constant values (e.g. built-in `CGColorSpace` names). Use `guard` for early exits.
- **Naming.** Name things after the film process (negative, print, printer lights, density, exposure in stops), not the implementation. Name units: `stops`, `log10`, `linear`, `display`.
- **Numbers.** Every magic number gets a name or a one-line source or reason. Shared constants live in `FilmLook`; don't repeat them.
- **Files.** One main type per file, named after it. Split a file once it does two jobs.
- **Comments: as few as possible.** Make the code explain itself through names and small functions. Comment only what code can't say: the physics or source behind a number, a non-obvious why, or a known limitation with its Linear issue. No narrating comments, no commented-out code. A comment that doesn't match the code is a bug.
- **Formatting** is whatever `swift format` produces. Don't hand-format against it.

## Owner preferences
Short answers that lead with the result. Plain language: explain jargon. Ask before outward-facing actions.
