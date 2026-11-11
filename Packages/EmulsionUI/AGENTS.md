# EmulsionUI

Shared SwiftUI components for the iOS and Mac apps: the rendered photo, adjustment panel and rulers, and later the look picker, before/after compare, grid, histogram and Liquid Glass styles (MOV-120).

- **Views only.** State and logic come from `EmulsionKit` (e.g. `AdjustmentGroup` defines the controls; this package only draws them).
- **Both platforms.** Every view builds for iOS and macOS. Platform differences go behind small `#if os(...)` adapters here, so the apps stay thin.
- **Visual direction (MOV-54):** ultra-minimal, photo-first, native Liquid Glass; reveal one Photos-style tick-mark adjustment ruler on demand. Keep selected controls in the owning editor, and support accessible increments/reset plus a neutral detent. Use system colors and grouped glass for controls; never add decorative blur to the grading canvas. Keep `ComponentGallery` debug-only; the iOS debug app opens it with `--component-gallery` for accessibility proof.
- **Glass rules (MOV-55/56, from Apple's "Adopting Liquid Glass" and HIG Materials):** glass is for the control layer only, never thumbnails or the photo. One glass surface per control group (`AdjustmentPanel` is a single sheet; controls on it use system fills, not more glass). Use `glassEffect` and system styles only, so Reduce Transparency, Increase Contrast and Reduce Motion are handled by the system.
- Follow `Apps/iOS/AGENTS.md` for SwiftUI rules (Observation, small views, `.task(id:)`, accessibility).
- **Rendering** always goes through the `RenderService` in the environment (`\.renderService`); never render on the main actor.
- Check it builds for both: `(cd Packages/EmulsionUI && swift build)` (macOS) plus the iOS app build.
