# SwiftUI app

- iOS 26 with Liquid Glass. Use system materials and controls before custom ones.
- **Observation:** `@Observable` models marked `@MainActor`. The owner holds them in `@State`; children get them via `@Environment` or plain properties, with `@Bindable` only for two-way bindings. Don't use `ObservableObject`, `@Published`, `@StateObject` or `@EnvironmentObject`.
- **Views** stay small and logic-free: extract a subview past about 50 lines. Use `.task`/`.task(id:)` for async work, `NavigationStack` with typed routes, `.foregroundStyle`.
- **Rendering** goes through `RenderService` (an actor); never render on the main actor. Inject dependencies through `@Environment` or initializers, not new singletons.
- **Regular iPhone and iPhone Duo are equal priority.** Build both properly; neither is an afterthought (MOV-119).
  - On Duo unfolded, use the whole landscape canvas with its own layout. Never a stretched phone UI. Examples: the photo large plus a persistent control panel, a grid plus a big preview, before/after across the fold.
  - Respect reserved regions (fold, camera) and use `ArrangementView` / adaptive layout APIs, not the hinge angle. Keep state when folding mid-edit.
  - Every UI PR shows proof on the iPhone 17 Pro simulator and the iPhone Duo simulator (folded and unfolded). That needs the Xcode 27.1 SDK.
- **Accessibility:** every control has a label and supports Dynamic Type.
- Folders are organized by feature (`Camera/`, `Library/`, `Editor/`), with shared models in `Model/`.
