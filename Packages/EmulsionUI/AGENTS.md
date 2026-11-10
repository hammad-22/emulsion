# EmulsionUI

Shared SwiftUI components for the iOS and Mac apps: the rendered photo, adjustment panel and sliders, and later the look picker, before/after compare, grid, histogram and Liquid Glass styles (MOV-120).

- **Views only.** State and logic come from `EmulsionKit` (e.g. `AdjustmentGroup` defines the controls; this package only draws them).
- **Both platforms.** Every view builds for iOS and macOS. Platform differences go behind small `#if os(...)` adapters here, so the apps stay thin.
- Follow `Apps/iOS/AGENTS.md` for SwiftUI rules (Observation, small views, `.task(id:)`, accessibility).
- **Rendering** always goes through the `RenderService` in the environment (`\.renderService`); never render on the main actor.
- Check it builds for both: `(cd Packages/EmulsionUI && swift build)` (macOS) plus the iOS app build.
