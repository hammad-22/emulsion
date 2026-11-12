import CoreGraphics
import EmulsionCore
import Foundation
import Observation

/// The camera screen's state: starts and stops the camera, switches lenses, focuses where
/// the user taps, shows the recipe live in the viewfinder, and adds each capture to the library
/// as an untouched original whose edit starts as the recipe.
@MainActor @Observable
public final class CameraModel {
    public enum Status: Sendable {
        case idle, starting, running, unauthorized, unavailable
    }

    public private(set) var status = Status.idle
    public private(set) var capabilities: CameraCapabilities?
    public private(set) var isCapturing = false
    /// The newest photo taken in this session.
    public private(set) var lastCapture: PhotoRecord?
    /// Where the user last tapped to focus (0…1 of the upright frame), until the reticle fades.
    public private(set) var focusPoint: CGPoint?
    /// Counts shutter presses, for the shutter blink and haptic.
    public private(set) var captureCount = 0
    /// The last camera problem, for the app to show. Set it to nil once shown.
    public var error: CameraError?
    /// Filled only while `recordsViewfinderTiming` is on (the debug overlay), so a release build
    /// doesn't change an observed property 30 times a second.
    public private(set) var viewfinderTiming = ViewfinderTiming()
    @ObservationIgnored public var recordsViewfinderTiming = false
    /// The look the viewfinder shows and captures start with (kept in the settings); a change
    /// shows on the next frame.
    public var recipe: Recipe {
        get { settings.recipe }
        set { settings.recipe = newValue }
    }

    private let source: any CameraSource
    private let store: PhotoStore
    private let settings: AppSettings
    @ObservationIgnored private var hasReportedViewfinderFailure = false
    @ObservationIgnored private var focusReset: Task<Void, Never>?
    /// How long the focus reticle stays up after a tap.
    @ObservationIgnored var focusIndicatorDuration: Duration = .seconds(1.5)

    public init(source: any CameraSource, store: PhotoStore, settings: AppSettings) {
        self.source = source
        self.store = store
        self.settings = settings
    }

    /// Starts the camera; does nothing while it's already starting or running. The renderer and
    /// the viewfinder's tables are prepared meanwhile, so the first frame doesn't wait for them.
    public func start() async {
        guard status != .starting, status != .running else { return }
        status = .starting
        let renderService = store.renderService
        // A renderer that can't be prepared now fails on the first frame instead; the camera
        // still starts.
        async let prepared: Void? = try? renderService.prepareViewfinder()
        let result: Result<CameraCapabilities, CameraError>
        do {
            result = .success(try await source.start(lens: capabilities?.lens ?? .wide))
        } catch {
            result = .failure(error)
        }
        _ = await prepared
        do {
            let started = try result.get()
            guard status == .starting else {
                // Stopped while starting: leave the camera off.
                await source.stop()
                return
            }
            capabilities = started
            status = .running
        } catch {
            status = error == .notAuthorized ? .unauthorized : .unavailable
            if error != .notAuthorized { self.error = error }
        }
    }

    /// Stops the camera (leaving the app, opening the library). Safe to call repeatedly.
    public func stop() async {
        guard status == .starting || status == .running else { return }
        status = .idle
        await source.stop()
    }

    /// Switches lens; ignored while a photo is being taken, so the capture finishes on the lens
    /// it started with.
    public func select(_ lens: CameraLens) async {
        guard status == .running, !isCapturing, lens != capabilities?.lens else { return }
        do {
            capabilities = try await source.select(lens)
        } catch {
            self.error = error
        }
    }

    /// Focuses and exposes at a point of the upright frame (0…1, top-left origin).
    public func focus(at point: CGPoint) async {
        guard status == .running else { return }
        focusPoint = point
        focusReset?.cancel()
        focusReset = Task { [focusIndicatorDuration] in
            try? await Task.sleep(for: focusIndicatorDuration)
            if !Task.isCancelled { focusPoint = nil }
        }
        await source.focusAndExpose(at: point)
    }

    /// Takes a RAW photo at the settings' resolution (12 MP on lenses without 48 MP) and adds it
    /// to the library with the recipe shown at the shutter press as its edit.
    public func capture() async {
        guard status == .running, !isCapturing, let capabilities else { return }
        isCapturing = true
        captureCount += 1
        defer { isCapturing = false }
        let look = recipe.adjustments
        let resolution = capabilities.resolution(for: settings.resolution)
        let photo: CapturedPhoto
        do {
            photo = try await source.capture(resolution)
        } catch {
            self.error = error
            return
        }
        do {
            lastCapture = try await store.add(photo.data, fileExtension: photo.fileExtension, look: look)
        } catch {
            self.error = .saveFailed
        }
    }

    /// The viewfinder with the current recipe, each frame rendered off the main actor and fitted
    /// within `maxDimension`. Newest only: while one frame renders, newer ones replace older ones.
    public func viewfinderImages(maxDimension: CGFloat) -> AsyncStream<CGImage> {
        let frames = source.frames()
        let renderService = store.renderService
        let (images, continuation) = AsyncStream.makeStream(of: CGImage.self, bufferingPolicy: .bufferingNewest(1))
        let delivery = Task { [weak self] in
            var frameNumber = 0
            for await frame in frames {
                guard let look = self?.viewfinderLook(frameNumber: frameNumber) else { break }
                frameNumber += 1
                let started = ContinuousClock.now
                let image: CGImage
                do {
                    image = try await renderService.viewfinderImage(frame, look, maxDimension: maxDimension)
                } catch {
                    self?.reportViewfinderFailure()
                    continue
                }
                if self?.recordsViewfinderTiming == true {
                    let shown = ContinuousClock.now
                    self?.viewfinderTiming.record(render: started.duration(to: shown), shownAt: shown)
                }
                continuation.yield(image)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in delivery.cancel() }
        return images
    }

    /// A viewfinder that can't render (the engine failed to load) says so once, instead of
    /// staying black without a word.
    private func reportViewfinderFailure() {
        guard !hasReportedViewfinderFailure else { return }
        hasReportedViewfinderFailure = true
        error = .unavailable
    }

    /// The recipe for one viewfinder frame. Artistic: the grain seed changes every frame so the
    /// grain looks alive rather than like a pattern fixed on the glass.
    func viewfinderLook(frameNumber: Int) -> Adjustments {
        var look = recipe.adjustments
        look.seed = Double(frameNumber % Adjustments.grainSeedCount)
        return look
    }

    /// The layer the viewfinder draws in, so the camera turns frames upright for it.
    public func attachViewfinder(_ layer: ViewfinderLayer) async {
        await source.attachViewfinder(layer)
    }
}
