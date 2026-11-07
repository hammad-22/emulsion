# EmulsionKit

Shared app logic for the iOS and Mac apps: the photo library (`PhotoStore`, `PhotoRecord`), rendering off the main actor (`RenderService`), settings and export (`AppSettings`, `PhotoLibrarySaver`). Later: look presets, import/export, metadata, CloudKit sync (MOV-120).

- **No UI.** No SwiftUI views here; shared views live in `EmulsionUI`. Only Foundation, Observation, Photos and `EmulsionCore`.
- **Both platforms.** Everything must build for iOS and macOS. If an API differs, put a small adapter behind `#if os(...)` here, never in the apps.
- **Feature logic lands here or in EmulsionCore**, so the iOS app (curated subset) and the Mac app (everything) never duplicate it.
- **Public API is what the apps need, nothing more.** Test-only accessors stay internal and are reached with `@testable import`.
- **Tests** use Swift Testing and run on both platforms:
  ```bash
  (cd Packages/EmulsionKit && swift test)
  (cd Packages/EmulsionKit && xcodebuild test -scheme EmulsionKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro')
  ```
  If the newest simulator runtime has no iPhone 17 Pro, add its OS to the destination (e.g. `,OS=26.2`).
  Each test gets its own folder (`TestPhoto.temporaryFolder()`) and its own `RenderService`, so tests can run in parallel.
