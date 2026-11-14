---
name: swift-organize
description: Reorganise Swift code in Emulsion so it reads well and scales, with no behaviour change. Splits large files, removes narrating comments, turns magic values into named constants and enums, and applies Apple's conventions. Use when asked to clean up, organise or make code more readable, and before a file passes about 300 lines.
---

# Swift organize (Emulsion)

This changes **how the code is laid out**, never what it does. It complements `swift-review` (which reviews a diff) and `/simplify`. Read `AGENTS.md` and the nested `AGENTS.md` of every folder you touch first; they win over this file.

## Ground rules
- **No behaviour change.** Tests, goldens, public API and file formats stay the same. If a rename of public API is clearly better, list it in the PR; never change a `Codable` key, a recipe field, a stored file name or a `UserDefaults` key.
- **Prove it.** Run the package tests, `swift format lint` and both app builds before and after. Goldens must not change.
- **Small, reviewable steps.** One package or feature folder per commit. Moves use `git mv` so history follows.
- **Don't fight open work.** Ask which files open PRs touch and leave them for later.

## 1. Comments: as few as possible
Delete a comment when the code already says it. Keep or write one only for:
- the physics, standard or source behind a number (with the unit);
- a non-obvious *why* (an ordering constraint, an Apple bug, a measured trade-off);
- a known limitation with its Linear issue;
- the safety argument on every `@unchecked Sendable` or `nonisolated(unsafe)`.

Rules:
- **One line per comment.** A comment is a single line (about 100 characters): what the value is, its unit, and `measured`, `sourced` or `artistic`. If the reason needs more than one line, the long form goes in the docs (`docs/ENGINE.md`, `docs/FILM-THEORY.md`, or the folder's `AGENTS.md`) under a heading named after the type, and the code keeps a short pointer (`See docs/ENGINE.md, "Digicam constants".`) on the type, not on every member.
- **One comment per group.** Related constants share one line above the group; don't repeat the same status word on each.
- **No history.** What a value used to be, what a review asked for, and which experiment failed belong in the commit, the PR or the docs.
- **Tests explain themselves by name.** A test's name says what it proves; keep a comment only for the source of an expected number.
- Doc comments (`///`) belong on `public` API and on anything whose contract isn't obvious from its name and types. One summary sentence; add parameters only when they need explaining. Don't document `private` helpers whose names are clear.
- Before deleting a comment that explains something real, move the knowledge into a name: rename the variable, extract a function, or name the constant.
- No section banners, no commented-out code, no "what changed" notes (that is the commit message), no restating the type or the next line.
- `// MARK: -` only in files that still have several sections after splitting. A file that needs many marks should be split instead.

## 2. Files: one job each
- One main type per file, named after it. An extension that adds a distinct role goes in `Type+Role.swift` (`FilmModel+Kernel.swift`).
- Aim for under about 300 lines for sources and 400 for tests. Over that, split by responsibility, not by line count:
  - protocol conformances into extensions (`extension PhotoStore: PhotoImporting`);
  - nested helper types into their own files once they have their own logic;
  - a view's subviews into their own `View` structs and files;
  - a test suite by behaviour (`RenderServiceExportTests`, `RenderServicePreviewTests`), sharing fixtures in a `…TestSupport.swift`.
- Group files in folders by feature (`Capture/`, `Library/`, `Editor/`, `Export/`), not by kind (`Models/`, `Helpers/`). SwiftPM picks up subfolders automatically; Xcode targets here use folder references, so check the app still builds.
- Order inside a type: stored properties, initialisers, the main API, then helpers; `private` things last or in a `private extension`.

## 3. Constants and enums
- A literal used twice, or once with a meaning that isn't obvious, gets a name. Put it where it belongs:
  - shared look and texture constants in `FilmLook`;
  - constants for one type as `private static let` on that type, or in a caseless `enum` namespace (`enum Layout { static let rulerHeight: CGFloat = 44 }`);
  - units in the name: `stops`, `log10`, `linear`, `seconds`, `points`.
- Replace stringly-typed or integer-coded choices with enums:
  - a fixed set of options → `enum` with `CaseIterable` when the UI lists it;
  - `String` raw values only where the value is stored or exchanged (then the raw value is part of the format; don't rename it);
  - identifiers for accessibility, launch arguments, `UserDefaults` keys, notification names and file names → one namespace enum per area, not scattered string literals.
- A `Bool` parameter that selects between two behaviours becomes an enum when the call site reads unclearly (`render(.preview)` over `render(true)`).
- A pair or triple of related values that travel together becomes a small `struct`.
- Prefer `let`, value types and immutable configuration. No global mutable state.

## 4. The Apple way
Check the current page on developer.apple.com before relying on an API. Follow:
- **Swift API Design Guidelines:** clarity at the point of use; name by role, not type; methods read as phrases; Boolean properties read as assertions (`isEmpty`); factory methods start with `make`; omit needless words; mutating/non-mutating pairs (`sort`/`sorted`).
- **Access control:** `private` by default, then internal; `public` only for what the apps need. Mark types `final` only when it matters.
- **Extensions for conformances** and for grouping related API.
- **Observation and SwiftUI:** `@Observable` models owned with `@State`, passed plainly or with `@Environment`; small views with no logic; view-specific constants in a private namespace; `ViewModifier` or a `View` extension for repeated styling; previews (`#Preview`) kept beside the view.
- **Swift Concurrency:** actors for shared state, structured concurrency, no GCD.
- **Typed errors:** `EmulsionError` cases over strings.
- **Swift Testing:** `@Suite` per behaviour, parameterised `@Test(arguments:)` over copy-pasted tests, shared fixtures in one place.
- **Formatting** is whatever `swift format` produces.

## 5. What not to do
- Don't add abstraction for its own sake: no protocol with one conformer, no wrapper that only forwards, no "Manager"/"Helper"/"Utils" types.
- Don't merge the deliberate Swift/Metal mirrors; keep their constant names identical.
- Don't reorder or rename anything in a `Codable` type's stored form.
- Don't touch generated or checked-in binary resources (metallibs, goldens, frozen scenes).

## Output
1. A short plan per folder: files to split, comments to drop, constants and enums to introduce.
2. The change, in commits per folder.
3. A report: files over the size guide before and after, comment lines before and after, every public rename, and the test, lint and build results. Say what you did not verify.

## Sources this skill draws on (ideas, not copied text)
- Apple: Swift API Design Guidelines (swift.org), the Swift Programming Language book (access control, extensions, enumerations), and the documentation for Observation, SwiftUI, Swift Concurrency and Swift Testing.
- This repo's `AGENTS.md` and the `swift-review` skill.
