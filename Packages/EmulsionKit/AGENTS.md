# EmulsionKit

Shared app logic for the iOS and Mac apps: the photo library (`PhotoStore`, `PhotoRecord`), rendering off the main actor (`RenderService`), the editor's controls and edit session (`AdjustmentGroup`, `EditSession`), settings and export (`AppSettings`, `PhotoLibrarySaver`), bundled sample photos. Recipes use `RecipeStore` for persistence and bounded JSON import; metadata and CloudKit sync remain later work (MOV-120).

- **No UI.** No SwiftUI views here; shared views live in `EmulsionUI`. Only non-UI Apple frameworks (Foundation, Observation, Photos, ImageIO, UniformTypeIdentifiers, CoreTransferable) and `EmulsionCore`.
- **Both platforms.** Everything must build for iOS and macOS. If an API differs, put a small adapter behind `#if os(...)` here, never in the apps.
- **Feature logic lands here or in EmulsionCore**, so the iOS app (curated subset) and the Mac app (everything) never duplicate it.
- **Public API is what the apps need, nothing more.** Test-only accessors stay internal and are reached with `@testable import`.
- **Library persistence:** decode missing optional schema fields with defaults; keep unreadable indexes intact or backed up, preserve readable records during recovery, and commit the index before changing visible library state. Surface write failures. Distinguish a missing index from an inaccessible one using the throwing read, not `fileExists`.
- **Tests** use Swift Testing and run on both platforms:
  ```bash
  (cd Packages/EmulsionKit && swift test)
  (cd Packages/EmulsionKit && xcodebuild test -scheme EmulsionKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro')
  ```
  If the newest simulator runtime has no iPhone 17 Pro, add its OS to the destination (e.g. `,OS=26.2`).
  Each test gets its own `TestLibrary` (folder and `RenderService`), so tests can run in parallel; the services share one `Renderer`, as the app has one (MOV-127), and keep thumbnails in a store the system never purges, so caching is checkable (MOV-130). Build test services through `TestLibrary`, not `RenderService()`. User-facing strings use `String(localized:bundle: .module)`.
