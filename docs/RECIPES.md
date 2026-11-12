# Recipes

A recipe is a named artistic adjustment snapshot for Emulsion's current built-in film model. It is not a stock file, a measured film match, an input transform, or a photo. Selectable negative/print models remain MOV-107. Descriptive curated names are Everyday, Warm Light, Quiet Color and Night Glow. User names are user-supplied; counsel review of the naming policy remains MOV-92.

## Version and compatibility policy

JSON format version **1** requires `formatVersion`, `engineModel`, `id` (UUID), `name`, `summary` and all eight adjustment values: exposure, warmth, tint, color, highlights, shadows, grain and halation. `engineModel` must equal `emulsion-default-v1`. This identifier describes the current renderer's look compatibility, not an app build number or a fitted stock. A future incompatible renderer must use another model identifier and define any supported conversion explicitly.

Only version 1 and this model are accepted. Unknown future or older versions and other models are rejected, with separate user-facing errors. There are no earlier published recipe formats and no invented migrations. Missing fields, invalid types, non-finite values and values outside the editor's documented ranges are rejected rather than clamped. Unknown keys are ignored; they must not introduce rendering semantics without a version change. Names are trimmed, nonempty, at most 80 characters and free of control characters; summaries are at most 240 characters and free of control characters. Combined name/summary UTF-8 is limited to 4 KiB so pathological combining-character sequences cannot create an unshareable saved look. Individual imports are limited to 64 KiB before decoding. Direct Codable decoding also validates the version, model and settings.

## Photo and collection behavior

The grain seed belongs to a photo and is absent from recipe JSON. Applying a recipe replaces the eight adjustment values, preserving the current photo's seed and original file. Edits continue through the existing EditSession persistence and render path; Reset restores the photo's default values. No recipe reference is needed to render an existing photo. Deleting or changing a saved look never changes photos already edited with it. InputContract selection remains based on the original source and is not part of a recipe.

The shared Looks picker saves the current edit, applies a curated or saved look, imports JSON through the system file picker, and shares JSON using the native share interface. Import saves a new independent identity and does not automatically apply it. This avoids an imported UUID replacing another saved or curated look. Repeated imports create independent copies.

User recipes live in `Application Support/Emulsion/recipes.json`, separate from `library.json`. The collection is bounded to 256 looks and 4 MiB, and validated on read. Writes are atomic and precede visible changes. A corrupt, future-version or inaccessible collection stays on disk untouched; saving/import/deleting stays disabled for that store instance. Relaunch after resolving the file problem retries the read. Individual invalid imports do not modify either collection or the photo library. Write failures retain visible state and surface an error.

## Integration

MOV-121 can use `Recipe.applying(to:)` for camera defaults and `EditSession.apply(_:)` after capture. Choose the capture's deterministic seed separately; do not store a shared recipe seed. The existing camera topic currently uses Adjustments and defines no competing Recipe model.

PR32's Duo ArrangementWorkspace, expanded inspector default, compare gesture arbitration and cached rendered-photo continuity are independent of this flow. During integration preserve its EditorContent and inspector; add LooksButton to its EditorToolbar's bottom bar and pass RecipeStore through the app environment. Do not replace its layout with main's older EditorContent. The same LooksButton is already used by the Mac editor.

## Apple references

- [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink) and [FileRepresentation](https://developer.apple.com/documentation/coretransferable/filerepresentation): native file sharing.
- [fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)): system JSON selection and security-scoped URL access.
- [Security-scoped resources](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()): balance successful access with release.
