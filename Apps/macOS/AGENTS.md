# macOS app

Native macOS 26 SwiftUI shell. Models, edit sessions, imports and rendering come from `EmulsionKit`; reusable views come from `EmulsionUI`.

- Read `Packages/EmulsionUI/AGENTS.md` for shared view rules. Keep Mac navigation and window layout here, without duplicating model or render code.
- Use a native sidebar and resizable photo/control split. A single window owns the open edit until coordinated multi-window editing is designed.
- Build with `xcodebuild -project Apps/macOS/Emulsion.xcodeproj -scheme Emulsion -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- Run the built app, add sample photos, edit, compare, switch photos and reopen to verify persistence. Keep screenshots for PR Proof. Also rerun the iOS walkthrough after shared UI changes.
