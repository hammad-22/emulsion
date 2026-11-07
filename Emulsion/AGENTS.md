# SwiftUI app

- iOS 26 with Liquid Glass. Use system materials and controls before custom ones.
- **Observation:** `@Observable` models marked `@MainActor`. The owner holds them in `@State`; children get them via `@Environment` or plain properties, with `@Bindable` only for two-way bindings. Don't use `ObservableObject`, `@Published`, `@StateObject` or `@EnvironmentObject`.
- **Views** stay small and logic-free: extract a subview past about 50 lines. Use `.task`/`.task(id:)` for async work, `NavigationStack` with typed routes, `.foregroundStyle`.
- **Rendering** goes through `RenderService` (an actor); never render on the main actor. Inject dependencies through `@Environment` or initializers, not new singletons.
- **iPhone Duo:** layouts must adapt to the folded and unfolded displays and respect reserved regions (needs the Xcode 27.1 SDK).
- **Accessibility:** every control has a label and supports Dynamic Type.
- Folders are organized by feature (`Camera/`, `Library/`, `Editor/`), with shared models in `Model/`.
