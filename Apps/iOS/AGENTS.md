# SwiftUI app

- iOS 26 with Liquid Glass. Use system materials and controls before custom ones.
- **Observation:** `@Observable` models marked `@MainActor`. The owner holds them in `@State`; children get them via `@Environment` or plain properties, with `@Bindable` only for two-way bindings. Don't use `ObservableObject`, `@Published`, `@StateObject` or `@EnvironmentObject`.
- **Views** stay small and logic-free: extract a subview past about 50 lines. Use `.task`/`.task(id:)` for async work, `NavigationStack` with typed routes, `.foregroundStyle`.
- **Rendering** goes through `RenderService` (an actor); never render on the main actor. Inject dependencies through `@Environment` or initializers, not new singletons.
- **Regular iPhone and iPhone Duo are equal priority.** Build both properly; neither is an afterthought (MOV-119).
  - On Duo unfolded, use the whole landscape canvas with its own layout. Never a stretched phone UI. Examples: the photo large plus a persistent control panel, a grid plus a big preview, before/after across the fold.
  - Respect reserved regions (fold, camera) and use `ArrangementView` / adaptive layout APIs, not the hinge angle. Keep state when folding mid-edit.
  - Every UI PR shows proof on the iPhone 17 Pro simulator and the iPhone Duo simulator (folded and unfolded). That needs the Xcode 27.1 SDK.
- **Screen idiom (MOV-55/56):** the library is an edge-to-edge grid under system toolbars (Select at the top, Import or Delete in the bottom bar). The editor is a neutral black, white-tinted workspace: toolbars stay monochrome beside the photograph, nothing is drawn over it (the title says "Original" while comparing), and the glass panel sits below or beside the photo, never on it.
- **Accessibility:** every control has a label and supports Dynamic Type.
- Folders are organized by feature (`Camera/`, `Library/`, `Editor/`). Models and app logic live in `Packages/EmulsionKit`, not in the app.
- **Run it before every app PR.** Build, then run the UI walkthrough on a fresh install. It adds the sample photos, edits, compares, rotates and saves to Photos, and keeps screenshots in the result bundle for the PR Proof:
  ```bash
  xcrun simctl uninstall booted com.hammad.emulsion; rm -rf /tmp/ui.xcresult /tmp/ui-shots
  xcodebuild test -project Apps/iOS/Emulsion.xcodeproj -scheme Emulsion -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -resultBundlePath /tmp/ui.xcresult
  xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path /tmp/ui-shots
  ```
  XCUITest's own landscape screenshots come out garbled; for landscape proof, take a frame from `xcrun simctl io booted recordVideo`.
