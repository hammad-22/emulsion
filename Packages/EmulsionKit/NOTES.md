# EmulsionKit notes

The reasoning behind EmulsionKit code that is too long for a one-line comment. Each section is
named after the type that points to it.

## AVCameraSource

- Follows Apple's AVCam sample: an actor whose executor is the capture session's serial queue, so
  every session call runs on that queue.
- Physical cameras only, never a virtual one: Bayer RAW requires a zoom factor of 1
  (AVCapturePhotoOutput.h, Bayer RAW rules), and virtual cameras change lenses by zoom. The same
  applies to `CameraLens`.
- **Viewfinder pixel format:** the camera's native full-range YCbCr, which Core Image reads
  directly with its color attachments; BGRA only if a device lacks it.
- **Rotation:** frames stay in sensor orientation; each carries the rotation that turns it upright
  (`CameraFrame`), so rotating the interface never rebuilds the pipeline. With the viewfinder's
  layer, the rotation coordinator's preview angle turns frames upright for the interface
  orientation the layer is shown in (AVCaptureDevice.h).
- **Lens switching (`use`):** swaps the input to the requested lens (or the wide lens), then
  re-applies the RAW formats and photo sizes, which belong to the device's active format. If the
  new lens has no RAW format, the previous input goes back with its RAW state; if that fails too,
  no input stays (`rawPixelFormat` is nil) so a later `start` sets the camera up again. `input`,
  `lens` and the RAW state always describe what the session runs. `swapInput` keeps the old input
  when the new one can't be added.
- **RAW format:** ProRAW when supported, else Bayer RAW, at the largest size. ProRAW must be enabled
  after the input is added, since RAW formats only exist with a video source. Bayer RAW must
  prioritize speed; ProRAW may use the output's maximum, quality (AVCapturePhotoOutput.h, RAW
  rules). The embedded preview (2048 px) is enough for the editor's "Original" view on a phone
  without decoding the RAW.
- **System pressure:** the camera reports the pressure and lowers its frame rate under it, which
  also lightens the viewfinder's film render. 20 fps from `serious`, as Apple's AVCam sample
  throttled (AVCaptureSystemPressure.h advises throttling there); 10 fps from `critical`, an
  artistic judgement to roughly halve the film render's cost again. From `shutdown` the system
  interrupts the session itself. The throttled rate is kept per device, since a lens keeps its rate
  while another one runs; `.invalid` frame durations restore the format's default rate.
- **Session notifications** are registered before the session starts, since `startRunning` itself
  may interrupt it (a camera another app holds). The session restarts itself after an interruption
  (AVCaptureSession.h). After a media services reset the session is restarted, as Apple's AVCam
  sample does; any other runtime error, or a restart that doesn't take, is reported as a failure
  the user can retry.
- **Focus:** a tap focuses and exposes once and turns on subject-area monitoring; when the scene
  changes the camera returns to continuous focus and exposure at the centre. A camera that can't be
  locked for configuration (another app holds it) keeps its current focus and exposure; there's
  nothing for the user to do.
- **Lens magnification** comes from the 35 mm equivalent focal lengths (AVCaptureDevice.h, iOS 26),
  or the field of view if one is unknown.

## CameraSource

- `frames()`: viewfinder frames, newest only: a slow consumer skips frames instead of queueing them.
  `events()`: interruptions, unrecoverable errors and system pressure, every event in order, since
  each changes what the camera screen shows. Each call to either starts a new stream and finishes
  the previous one (`SourceStream`); the consumer's loop ends when the source goes away.
- `start(lens:)` falls back to the wide lens if the device lacks the requested one, and asks for
  camera access first if the user hasn't decided yet.
- `focusAndExpose(at:)` takes a point of the upright frame as displayed: 0…1, top-left origin.
  `FrameGeometry` converts it to the sensor-native point of interest `AVCaptureDevice` expects
  ((0,0) top-left, (1,1) bottom-right per `focusPointOfInterest`).
- `attachViewfinder` hands over the viewfinder's layer so frames can be turned upright for the
  interface orientation it's shown in. `ViewfinderLayer` is `@unchecked Sendable` because the
  camera never touches the layer itself: it only passes it to `AVCaptureDevice.RotationCoordinator`,
  which keeps it weakly and reports on the main queue (AVCaptureDevice.h), as Apple's AVCam sample
  does from its capture actor.

## CameraEvent

Events happen to a running camera on its own, not at the app's request. `interrupted` resumes by
itself (`interruptionEnded`); `failed` is an error the camera couldn't recover from, and starting it
again may work. Interruption reasons map `AVCaptureSession.InterruptionReason`:
`multipleForegroundApps` is another app on screen beside this one (Stage Manager, iPhone Duo's split
screen); `other` covers the rest (the app moved to the background, a call took the audio). Pressure
levels map `AVCaptureDevice.SystemPressureState.Level`.

## CameraFrame

The rotation (0, 90, 180 or 270 degrees, clockwise) travels with the frame instead of being applied
by the capture connection: rotating video data output buffers rebuilds the capture pipeline
(AVCaptureSession.h, `videoRotationAngle`), which would stall the viewfinder on every interface
rotation. `init(drawing:)` draws on the CPU into a BGRA buffer tagged sRGB, like a camera frame
tagged with its color space, so the stand-in camera and tests make no GPU context (MOV-127).

## CameraModel

- Owns the camera screen's state: starts and stops the camera, switches lenses, focuses where the
  user taps, shows the recipe live in the viewfinder, and adds each capture to the library as an
  untouched original whose edit starts as the recipe shown at the shutter press.
- `status` combines `lifecycle` (what the app asked for and how that went; never `interrupted`) with
  a pause the system imposed. An interruption queued before `stop` is ignored, so the next start
  reports a camera that's still taken instead of looking paused.
- `start` prepares the renderer and the viewfinder's tables while the camera starts, so the first
  frame doesn't wait. A renderer that can't be prepared fails on the first frame instead; the
  camera still starts. Denied or restricted access is shown by the screen, without an alert.
- `stop` also stops a camera that failed while running, so a later recovery can't restart it behind
  the app. It forgets an interruption: a camera that's still taken reports it again on the next
  start.
- Lens switches are ignored while a photo is in flight, so the capture finishes on its lens.
- `viewfinderTiming` is filled only while `recordsViewfinderTiming` is on (the debug overlay), so a
  release build doesn't change an observed property 30 times a second.
- A viewfinder that can't render (the engine failed to load) reports `unavailable` once instead of
  staying black without a word.
- Artistic: the viewfinder's grain seed changes every frame, so grain looks alive rather than like a
  pattern fixed on the glass.

## MockCameraSource

A stand-in camera for the Simulator (which has none) and tests: the bundled sample photos as a live
viewfinder, one per lens, panning slowly so it visibly moves. Capture returns the sample's JPEG:
there's no DNG to bundle, since the samples are synthetic renders, not camera files. Frames are drawn
on the CPU, so the stand-in makes no GPU context of its own: the renderer's stays the only one
(MOV-127). Frames are 768 × 1024 (portrait 3:4, like a phone held upright) at about 30 fps; crops
use whole pixels inside the sample so every frame is exactly that size. Emitted interruptions pause
frames, as a real session's do.

## PhotoStore

- Originals live in one folder (Application Support by default) with an index of their
  non-destructive edits (`library.json`). The index is written before the library changes, so what
  the app shows is what the next launch finds.
- `lastError` holds problems no caller could be told about directly (loading, saving an edit,
  deleting). A failed save is reported once until a save succeeds, so a full disk isn't reported on
  every slider rest.
- **Imports:** the original is prepared off the main actor (`OriginalImporter`), then committed
  against the latest library with no suspension between reading the current photos, committing and
  publishing, so imports cannot restore a deleted record or overwrite an intervening edit.
  Cancellation before the commit removes only this import's files; a committed import succeeds even
  if its caller is cancelled immediately afterward. Staging folders are nested (`.import-…`) so they
  are never mistaken for recoverable originals, and the final move fails rather than overwrite an
  existing file.
- **Recovery:** an index that can't be read right now (file protection) is not corrupt: it is kept
  as it is and never overwritten. A corrupt index is moved aside as `library-unreadable-….json` so its
  edits can still be recovered, and records that still decode keep their edits; other originals
  are listed again with the default look. The recovered list is written at once, so the next launch
  finds it rather than no index.
- **Exposure anchors:** saved anchors are handed to the render service at launch; it measures again
  for an original that changed. A newly measured anchor is saved at once, then any others measured
  within `exposureAnchorSaveDelay` are batched, so opening a library of unmeasured RAWs writes the
  index about once a second, not once per photo.

## PhotoRecord and StoredExposureAnchor

Only a record's ID and file name are required: any other field missing from the index gets a
default, so adding a field never makes an existing library unreadable (MOV-128). The exposure anchor
(MOV-134) is RAW only, saved after the first develop so a relaunch develops with it instead of
measuring the file again (MOV-141). It is a cache: one that doesn't decode is measured again rather
than failing the record. It belongs to the file it was measured from: `Source` records the file's
size and modification date, read from the file system each time because `URL.resourceValues`
caches on the URL, which would hide a change.

## Adjustments defaults

Grain seeds are whole numbers below 1024: small whole numbers keep float precision exact in the grain
kernel. A photo's seed is derived from its ID so re-renders, exports and resets match, and photos
differ.

## RecipeStore and RecipeTransfer

Saved looks are separate from the photo library. A failed read never enables an overwrite; a missing
file is a new collection, not an unreadable one. Reads are bounded even when a provider doesn't
report a reliable file size. An imported recipe gets a new identity, so it never overwrites a saved
or curated look, and importing doesn't apply it. Shared recipes are written to a unique temporary
folder each time, so concurrent shares stay independent; the system purges temporary files.

## TemperatureScale

The Temperature ruler's scale is negative mired (−10⁶ / kelvin). Equal steps in mired are roughly
equal visible steps at any temperature, where equal steps in kelvin are coarse at tungsten and
imperceptible at shade. It is negated so the ruler increases with the kelvin setting, which renders
warmer, the way Warmth does.

## RenderService

- **Preview size:** editor previews are developed and rendered no larger than
  `maxPreviewDimension` (2560 px). A phone screen's long edge is about that (2622 px on iPhone 17
  Pro), and a larger window, such as a 5K Mac display, only scales the preview up: before the cap, 12
  cached develops at a 5K window held about 585 MB. Exports are always full size.
- **Preview cache:** develops are kept within `previewCacheBytes` (half-float RGBA, 8 bytes a pixel),
  least recently used first, instead of 12 by count; the newest is always kept.
- **Order:** library work runs on this actor one job at a time. Thumbnails ask at `.utility`
  (`priority(forMaxDimension:)`) and the editor at `.userInitiated`, and the actor's default executor
  runs higher-priority jobs first, so a slider step jumps queued thumbnails: 343–383 ms → 10–23 ms
  behind eight 12 MP thumbnails (`RenderQueueProbe`, Mac). That is runtime behaviour, not a documented
  guarantee; the probe shows if it changes. A thumbnail stored on disk is read
  before the actor is asked, so it never waits behind a render. A render checks for cancellation
  again after its develop, so a superseded slider step skips its look render.
- **Exports stay on the actor** (MOV-163), at the editor's priority: once running, an export holds
  the actor until it's done, and a slider step asked for meanwhile waits for the rest of it. A
  `.utility` export was tried and dropped: it also runs on slower threads, so saving took longer. Running exports beside previews would mean a full-size
  RAW decode at the same time as a preview's decode of the same file, which MOV-147 found unsafe in
  some decoder states, and both peaks at once (2.2–2.3 GB for a 48 MP export). Revisit after
  MOV-147's owned-buffer develop lands, with peak memory measured on a device.

## ThumbnailFiles

- Rendered thumbnails (up to 512 px) are kept as JPEG files in Caches/Emulsion/Thumbnails, so a
  relaunched library shows them without developing every visible photo again; the system may
  delete the folder when space is short.
- A file's name covers the photo (its URL) and, hashed, its file's size and modification date, the
  whole edit and the size, so any change misses instead of showing a stale thumbnail. A folder per
  build (app version and executable), so a new engine never shows an old build's renders; other
  builds' folders are removed on the first write.
- Bounded at `byteLimit`: past it, the least recently shown files (by modification date, touched on
  every read) are deleted down to three quarters of it.
- JPEG at quality 0.9 is a deliberate, artistic trade: a stored thumbnail is not bit-identical to a
  fresh render, which only the library grid shows. Reading happens off the main actor; `cachedThumbnail`
  only looks in memory.

## LatestRenderCache

Keeps the latest editor-sized render of each photo, so a photo view rebuilt in a new layout (folding
or unfolding iPhone Duo, opening the editor from the library preview) shows the photo at once while
it renders again at its new size. It never holds an original. Thumbnail-sized renders are skipped:
the grid would otherwise push out the photo being edited, and `ThumbnailCache` already keeps those.
The app's store is an `NSCache` the system may purge whenever memory is short.

## AppSettings

The camera's recipe is kept as a snapshot (its encoded JSON), like a photo's edit, so it survives
the recipe being deleted from the saved looks; missing or unreadable reads as the first curated look.
`CuratedLooks` is a constant, non-empty list (EmulsionCore's `RecipeTests`), so the precondition on
it can't fail.
