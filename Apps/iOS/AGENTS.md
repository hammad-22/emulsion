# SwiftUI app

- iOS 26 minimum with Liquid Glass. Use system materials and controls before custom ones. Duo arrangements, reserved regions and toolbar axis behavior require iOS 27.1; isolate them with availability guards while retaining the iOS 26 ordinary-iPhone layout. This is the justified exception to the root no-fallback rule (MOV-62).
- **Observation:** `@Observable` models marked `@MainActor`. The owner holds them in `@State`; children get them via `@Environment` or plain properties, with `@Bindable` only for two-way bindings. Don't use `ObservableObject`, `@Published`, `@StateObject` or `@EnvironmentObject`.
- **Views** stay small and logic-free: extract a subview past about 50 lines. Use `.task`/`.task(id:)` for async work, `NavigationStack` with typed routes, `.foregroundStyle`.
- **Rendering** goes through `RenderService` (an actor); never render on the main actor. Inject dependencies through `@Environment` or initializers, not new singletons.
- **Regular iPhone and iPhone Duo are equal priority.** Build both properly; neither is an afterthought (MOV-119).
  - On Duo unfolded, use the whole landscape canvas with its own layout. Never a stretched phone UI. Examples: the photo large plus a persistent control panel, a grid plus a big preview, before/after across the fold.
  - Respect reserved regions (fold, camera) and use `ArrangementView` / adaptive layout APIs, not the hinge angle. Keep state when folding mid-edit.
  - Every UI PR shows proof on the iPhone 17 Pro simulator and the iPhone Duo simulator (folded and unfolded). That needs the Xcode 27.1 SDK.
- **Screen idiom (MOV-54/55/56):** the camera is the root screen (MOV-60/121): neutral black, the viewfinder aspect-fit, controls below it in portrait and in a trailing rail when wide; the recipe strip lies over the viewfinder's bottom edge on demand and is always visible on Duo unfolded; frames go straight to a layer, never through SwiftUI state. The library is an edge-to-edge grid under system toolbars, following the system appearance. The editor is a neutral black, white-tinted workspace; the photo stays aspect-fit, without decorative overlays; the title says "Original" while comparing. Keep edit state, the selected adjustment and the library preview above layout branches so folding, hiding and rotation keep them.
  - Compact (iPhone, Duo folded): Adjust reveals one Photos-style ruler on a glass panel; hidden by default.
  - Expanded (a division region, active or not, or regular width and height; iOS 27.1): system split arrangements. Library: a 4-column grid beside a preview pane (photo, date, RAW/Edited, Edit Photo). Editor: photo beside `AdjustmentInspector` (every group on one glass sheet), shown by default; an explicit Adjust tap overrides the default in both postures. Hiding drops the split's axes so the photo view isn't rebuilt; `RenderService.latestRender` covers rebuilds across fold/unfold.
  - Active division/occlusion regions displace the image into a contiguous usable rectangle; system navigation owns vertical bars. Never infer a model from device dimensions. Native Duo fold proof remains open (MOV-62/63).
- **Accessibility:** every control has a label and supports Dynamic Type.
- Folders are organized by feature (`Camera/`, `Library/`, `Editor/`), with helpers used by several features in `Shared/`. Models and app logic live in `Packages/EmulsionKit`, not in the app.
- **Run it before every app PR.** Build, then run the UI walkthrough on a fresh install. The camera walkthrough runs on the Simulator's stand-in camera (the sample photos as a live viewfinder); the library walkthrough launches with `--library`. It adds the sample photos, edits, compares, rotates and saves to Photos, and keeps screenshots in the result bundle for the PR Proof:
  ```bash
  xcrun simctl uninstall booted com.hammad.emulsion; rm -rf /tmp/ui.xcresult /tmp/ui-shots
  xcodebuild test -project Apps/iOS/Emulsion.xcodeproj -scheme Emulsion -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -resultBundlePath /tmp/ui.xcresult
  xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path /tmp/ui-shots
  ```
  The walkthrough covers the phone layout only; it cannot select a Duo pose. Set Duo poses with T3 `agent-device fold closed|half-open|open` or Xcode Device Hub's Closed / Partially Open / Open buttons, on a simulator of your own with your own bundle ID. Capture the inner display with `xcrun simctl io <udid> screenshot --display primary-1`. Record which tool and pose each proof capture used, and say so when a pose could not be verified; never fake a pose with generic UI clicks or simctl taps.
  Launch with `--viewfinder-timing` (debug builds) to show the viewfinder's frame time and rate.
