# Emulsion

A free, open-source film lab for iPhone (Mac later): RAW and log footage in, a simulated negative → print film process out. **The engine is the product**: fast, honest about what it models, and verified.

- Background: `docs/ENGINE.md` (how it works), `docs/DECISIONS.md` (owner decisions), `docs/RESEARCH.md`, `docs/MARKET-RESEARCH.md`.
- Constant sources: `docs/CONSTANTS.md` (non-film engine constants), `docs/DIGICAM.md` (the digicam process).
- Film physics for E2 work: `docs/FILM-THEORY.md` (equations, sources, what the engine models vs approximates, gap list) and `docs/STOCK-DATA.md` (datasheet inventory). Read both before changing the film model.
- Work: Linear team **Emulsion** (key `MOV`). GitHub: `hammad-22/emulsion` (open source, AGPL-3.0-only).
- This file is the single source of rules for every coding agent (Codex reads it directly; `CLAUDE.md` imports it). Folder-specific rules live in nested `AGENTS.md` files: `Packages/EmulsionCore/Kernels/`, `Packages/EmulsionCore/Tests/`, `Packages/EmulsionKit/`, `Packages/EmulsionUI/`, `Apps/iOS/`, `Apps/macOS/`. Read the nested file before editing in that folder.

## Stack
iOS 26 / macOS 26 only, iPhone 17 Pro and iPhone Duo as targets. Swift 6.4 toolchain, SwiftUI with Liquid Glass, Core Image color kernels compiled to Metal libraries, SwiftPM. No third-party dependencies yet; any new one needs a reason and a license check.

## Layout
- `Packages/EmulsionCore/`: the engine package. Every look decision lives here.
  - `Sources/EmulsionCore/`: film math (`FilmModel`), input transforms (`ColorSpaces`), develop (`Developer`; `RAWDecoder` keeps one RAW file's decoder alive for white balance changes), render graph and export (`Renderer`), stock files (`Resources/Stocks/*.json`, loaded through `FilmStock`; the default is `FilmLook.stock`), texture constants (`FilmLook`), kernel argument packing (`FilmModel+Kernel`). The non-film digicam process (`Adjustments.process`, docs/ENGINE.md "Non-film looks"): `Renderer+Digicam`, `DigicamModel` (Swift mirror), `DigicamLook` (constants).
  - `Kernels/`: GPU kernels, `Emulsion.ci.metal` (film) and `Digicam.ci.metal` (digicam), linked into one metallib; must match the Swift mirrors. Compiled `.metallib`s are checked in under `Resources/Kernels/`.
  - `Sources/EmulsionFixtures/`: synthetic test images. `Tests/`: the test suite, with visual regression goldens in `Tests/EmulsionCoreTests/Goldens/` and frozen CC0 photos in `Scenes/`.
  - `Sources/EmulsionFit/` + `Sources/emulsion-fit/`: offline stock fitting (`emulsion-fit` CLI: manifest and reference-data loader and checks, bounded least squares, negative-curve fit). `Sources/EmulsionFit/Resources/StockData/<stock>/` holds the provenance manifests and the fitted stock files (`negative-fit.stock.json`; parameters and provenance only, not loaded by the engine until MOV-25). The traced curve CSVs are not in the repo (`docs/DECISIONS.md`, 12 Nov 2026): they are local reference data, pinned by SHA-256 in the manifests; never commit them. Not a library product, so no app can link it. The tracing tools are in `Tools/stock-digitizing/`.
- `Packages/EmulsionKit/`: shared app logic for iOS and Mac (library, `RenderService`, camera capture, editor controls, settings, export, sample photos). No UI.
- `Packages/EmulsionUI/`: shared SwiftUI components (rendered photo, sliders, photo import).
- `Apps/iOS/`: the iOS app (`Emulsion.xcodeproj`, sources in `Emulsion/`, UI walkthrough in `EmulsionUITests/`). Opens on the camera; the library and editor are behind it.
- `Apps/macOS/`: minimal native Mac shell on the same packages (`Emulsion.xcodeproj`); library, edit and compare.
- `Tools/`: `build-kernels.sh` rebuilds the metallibs; `make-sample-photos.swift` regenerates the bundled sample photos; `color-references/` generates the colour-science test references (offline Python, never shipped); `review-renders.sh` renders full-resolution before/after look reviews from local CC0 samples.

## Commands
Run these yourself to verify every change. A change isn't done until they pass.
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sh Tools/build-kernels.sh                                    # after any .metal change (both sources, one metallib)
(cd Packages/EmulsionCore && swift test)                     # must stay green
(cd Packages/EmulsionKit && swift test)                      # app logic; also on iOS, see its AGENTS.md
(cd Packages/EmulsionUI && swift test)                       # shared control interaction tests
.venv/bin/python -I Tools/color-references/generate_input_references.py    # after changing input reference samples
.venv/bin/python -I Tools/color-references/generate_delta_e_references.py  # after changing ΔE / chart references
.venv/bin/python -I Tools/color-references/generate_ssim_references.py      # after changing SSIM references (all three: pip install -r Tools/color-references/requirements.txt)
(cd Packages/EmulsionCore && EMULSION_PERF=1 swift test --filter PerformanceProbe)  # Mac timings
(cd Packages/EmulsionCore && EMULSION_UPDATE_GOLDENS=1 swift test --filter VisualRegression)  # accept an intended look change (Tests/AGENTS.md)
Tools/review-renders.sh [base-ref]                           # full-resolution before/after of the local CC0 samples for look reviews
(cd Packages/EmulsionCore && swift run emulsion-fit dyes --stock <id> --out <dir>)  # dye set + printing density (MOV-88; local standards tables, `--standards`)
(cd Packages/EmulsionCore && swift run emulsion-fit negative --stock kodak-vision3-250d-5207 --out /tmp/fit)  # fit a stock; also `list`, `check`
swift format lint --recursive Packages Apps Tools            # style (config: .swift-format)
```
Stock-data checks and `emulsion-fit` read the local reference data (traced curves, never committed) from `EMULSION_REFERENCE_DATA`, else `~/Documents/Emulsion Research/datasheet-tracings`; `swift test` skips those checks when the folder is missing.

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
- **Leave it cleaner.** Fix stale comments and dead code in the files you touch. For layout (file size, comments, constants, enums), follow the organize skill (`.agents/skills/swift-organize/SKILL.md`).
- **Prove it in the PR: before and after, visually.** Every PR has a **Proof** section (template in `.github/pull_request_template.md`) that a reviewer can judge without checking out the branch:
  - Start it with one or two lines under **What to look for**: what the reviewer should see change, and where.
  - Show **before and after side by side**, same scene, same size, same settings except the change; "before" is the base branch.
  - Pick the medium by the change: screenshots for anything static (layout, text, a color, a render); a short screen recording for anything with motion or interaction (animation, transition, gesture, scrolling, live slider drags, capture flow). When unsure, record.
  - UI changes: iOS Simulator (`xcrun simctl io booted screenshot|recordVideo`) on iPhone 17 Pro and Duo, light and dark when it matters, and a device when it matters.
  - Engine and look changes: before/after renders of a reference fixture at whole-photo size plus a 100% crop where the change shows, with the measured numbers.
  - Only when nothing visible can change (docs, tests, refactors): say "No visual change" and why; for refactors, give the evidence (goldens unchanged).
  - For third-party-derived data, publish residual numbers, not plots of the source curves. Proof uses only media we may publish (synthetic or CC0-derived); never the owner's or third-party photos.
  - **Embed, don't link:** images appear inline in the description (`<img src="…" width="360">` in a Before | After table), never as a text link the reviewer has to click. Recordings appear inline too: a GIF embedded the same way, with a link to the full video beside it if there is one.
  - Proof images and recordings go on a `proof/<issue>` branch (e.g. `proof/mov-54`), linked from the PR by a commit-pinned `raw.githubusercontent.com/.../<sha>/...` URL. Never commit them to `main` or a feature branch (MOV-131).
- **CI test crashes:** inspect the `test-diagnostics-<run>-<attempt>` artifact for the test log and macOS crash reports (MOV-127). Keep the failing exit status; don't mask crashes with retries.
- **Run the app in the Simulator** for any app change; don't stop at "it compiles". Use the iPhone 17 Pro and iPhone Duo simulators.
- **PR descriptions** cover what, why, proof, testing and the Linear issue. No attribution footers in PR descriptions and no `Co-Authored-By` lines in commit messages.
- **Review before the PR, then open it as a draft:**
  1. On the finished branch, run a simplify pass (`/simplify` in Claude Code) and apply the fixes.
  2. Run the Swift review skill (`.agents/skills/swift-review/SKILL.md`; `/swift-review` in Claude Code).
  3. Run a bug review: `/code-review high` on the branch diff (or Codex's code review). For risky engine or color-pipeline changes, note in the PR that `/code-review ultra` is recommended; only the owner can launch it.
  4. Investigate every finding and mark it ACCEPT or REFUTE, with proof (a reproduction, file:line or a test). Fix what's accepted, adding a regression test for each real bug.
  5. Open the PR as a **draft** (`gh pr create --draft`, or `gh stack submit --draft`) with the verdicts in a PR comment.
  6. Mark it ready (`gh pr ready`) once CI is green.
- **Risk level, and who approves the merge** (owner, 27 Nov 2026; modeled on how AI review tools gate automatic approval). Every PR description states **Risk: low, medium, high or critical** with one line of why. The level comes from what the change does, not from its size.
  - **Low:** docs and agent instructions, tests, comments, styling with no layout change, small behavior-neutral code changes (tests and goldens unchanged), and code compiled only into the Lab research build.
  - **Medium:** ordinary app changes: screens, app logic, new features and settings.
  - **High:** shared or foundational code: `RenderService`, capture, export, shared components used by more than one app, public API of the packages, dependencies, build settings.
  - **Critical:** anything that changes pixels or data: film engine and kernels, color and RAW input, looks and their defaults, goldens; stored formats (library, recipes) and migrations; licensing; CI and secrets; deleting data.
  - **Paths that are never low**, whatever the description says: `Packages/EmulsionCore/Kernels/`, `Resources/Kernels/`, `Resources/Stocks/`, `Tests/**/Goldens/`, `FilmModel*`, `Developer*`, `RAWDecoder*`, `LICENSE`, `NOTICE`, `.github/workflows/`, and any `Codable` stored type.
  - **Only low merges without the owner.** The parent session merges a low PR when all of these hold: it is not a draft, CI is green on the latest commit, the review ran on that commit with no open finding, verdicts are recorded, and it carries no `do-not-merge` or `manual-review` label. The parent re-checks the stated level against the diff; a missing or doubtful level counts as medium.
  - **Medium, high and critical need the owner's approval for that PR.** The parent marks it ready when the same conditions hold, points the owner at the Proof section, and merges only after their yes. Risk decides who approves; it never excuses a finding. Stacks merge bottom-up.

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
- Every new input declares its `InputContract` (`docs/ENGINE.md`, "Input contracts"); never describe a display-referred source as scene light.
- Don't call anything "physical", "accurate" or "like stock X" without a measurement or a primary source. Label artistic choices as artistic.
- No third-party copyleft code or data (GPL, AGPL, LGPL, CC BY-SA) in the engine or apps: the project is AGPL-3.0-only and the owner must hold every right (MOV-94). No film brand names in the product (MOV-92).
- Don't add per-pixel iterative solves to the live preview path without profiling on device.
- Never set `CIRAWFilter.contrastAmount` to 0, and never let a look or export render read Apple's lazy RAW decode: only `RAWDecoder.negative` renders it (and the exposure anchor's 256 px thumbnails). It corrupts whole tiles (MOV-147, `docs/ENGINE.md`).
- **Looks are judged against real references, first.** Before building or changing anything that affects how a photo looks (grain, halation, colour, tone, light leaks, a new look):
  1. Use references that match the look: real scans of that film stock, or real photos from that kind of camera for non-film looks. Never judge one stock against another stock's scans. References are local, look-only and never committed.
  2. If no matching references exist, say so and label the result "not yet checked against real film". Datasheet values and what was learned from other stocks are a starting point, not proof.
  3. Measure the target across the whole frame, not only where the effect is strongest.
  4. Show the gap between the references and the current render before building.
  5. Judge the result side by side with the references at the same scale, at whole-photo size and at 100%. A datasheet match alone is not acceptance.
  6. Review renders use a different grain seed per photo, as the app does, and differ only in the thing being compared.

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
- **Files.** In the engine (`EmulsionCore`, kernels): one main type per file; a distinct role goes in `Type+Role.swift`. In the apps, `EmulsionUI` and `EmulsionKit`: one file per screen or reusable component, named after its main type. Small subviews, styles and helpers used only by it stay in that file as `private` types. A type gets its own file once something else uses it or the file passes about 300 lines. At our size file count made no measurable build-time difference (MOV-185); group for the reader.
- **Folders.** By feature (`Camera/`, `Library/`); past about 8 files, subfolders named after what they hold (`Viewfinder/`, `Rendering/`), never `Views/`, `Models/` or `Helpers/`.
- **Reuse across apps is why this is one repository** (owner, 26 Nov 2026). A view with no app-specific dependency starts life in `EmulsionUI`; the apps keep screens, navigation, toolbars and debug hooks.
- **New code follows these rules now; existing files are regrouped only under MOV-185**, once the parent clears the folders. Don't move or merge existing files on your own.
- **Comments: as few as possible.** Make the code explain itself through names and small functions. Comment only what code can't say: the physics or source behind a number, a non-obvious why, or a known limitation with its Linear issue. No narrating comments, no commented-out code. A comment that doesn't match the code is a bug.
- **Formatting** is whatever `swift format` produces. Don't hand-format against it.

## Owner preferences
Short answers that lead with the result. Plain language: explain jargon. Ask before outward-facing actions.
