# EmulsionKit

Shared app logic for the iOS and Mac apps: the photo library (`PhotoStore`, `PhotoRecord`), rendering off the main actor (`RenderService`), the editor's controls and edit session (`AdjustmentGroup`, `EditSession`), settings and export (`AppSettings`, `PhotoLibrarySaver`), camera capture (`Capture/`: `CameraModel`, `CameraSource` with `AVCameraSource` on iOS and `MockCameraSource` for the Simulator and tests), bundled sample photos. Recipes use `RecipeStore` for persistence and bounded JSON import; metadata and CloudKit sync remain later work (MOV-120).

- **No UI.** No SwiftUI views here; shared views live in `EmulsionUI`. Only non-UI Apple frameworks (Foundation, Observation, Photos, ImageIO, UniformTypeIdentifiers, CoreTransferable) and `EmulsionCore`; for capture only, also AVFoundation, CoreVideo and QuartzCore's `CALayer` (the rotation coordinator needs the viewfinder's layer), still no views.
- **Both platforms.** Everything must build for iOS and macOS. If an API differs, put a small adapter behind `#if os(...)` here, never in the apps.
- **Feature logic lands here or in EmulsionCore**, so the iOS app (curated subset) and the Mac app (everything) never duplicate it.
- **Public API is what the apps need, nothing more.** Test-only accessors stay internal and are reached with `@testable import`.
- **Library persistence:** decode missing optional schema fields with defaults; keep unreadable indexes intact or backed up, preserve readable records during recovery, and commit the index before changing visible library state. Surface write failures. Distinguish a missing index from an inaccessible one using the throwing read, not `fileExists`.
- **Imports:** `PhotoStore.add` and `addSamples` are async. `OriginalImporter` prepares original bytes on its actor; commit against the current library on the main actor without suspension before publication. Cancellation before commit cleans only import-owned files; a committed import succeeds. Keep edits/deletes made during preparation.
- **One open photo.** `EditSession` marks its photo open on `RenderService` (`open`/`close`), which keeps that photo's `RAWDecoder` so white balance changes don't decode the file again (MOV-137). Never keep more than one: a decoder holds the file's bytes and Apple's decode. Slider timing lives in `SliderDragProbe` (`EMULSION_PERF=1`); run it before and after any change to the preview path.
- **White balance rulers** are ordinary `AdjustmentControl`s whose key paths carry the photo's as-shot white balance (`Adjustments+WhiteBalanceRulers`); `AdjustmentGroup.controls(whiteBalanceAsShot:)` has none for photos that aren't RAW.
- **Tests** use Swift Testing and run on both platforms:
  ```bash
  (cd Packages/EmulsionKit && swift test)
  (cd Packages/EmulsionKit && xcodebuild test -scheme EmulsionKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro')
  ```
  If the newest simulator runtime has no iPhone 17 Pro, add its OS to the destination (e.g. `,OS=26.2`).
  Each test gets its own `TestLibrary` (folder and `RenderService`), so tests can run in parallel; the services share one `Renderer`, as the app has one (MOV-127), and keep thumbnails in a store the system never purges, so caching is checkable (MOV-130). Build test services through `TestLibrary`, not `RenderService()`. Tests pass their own `AppSettings(defaults:)` suite via `TestLibrary.settings`, never `UserDefaults.standard`. User-facing strings use `String(localized:bundle: .module)`.
