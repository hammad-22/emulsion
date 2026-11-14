import CoreGraphics
import EmulsionCore
import Foundation
import Observation

/// The camera screen's state; each capture joins the library as an untouched original whose
/// edit starts as the recipe.
@MainActor @Observable
public final class CameraModel {
    public enum Status: Equatable, Sendable {
        case idle, starting, running, unauthorized, restricted, unavailable
        /// Started, but the system has paused the camera; it resumes by itself.
        case interrupted(CameraInterruption)

        init(startFailure error: CameraError) {
            switch error {
            case .notAuthorized: self = .unauthorized
            case .restricted: self = .restricted
            default: self = .unavailable
            }
        }
    }

    public var status: Status {
        if lifecycle == .running, let interruption { .interrupted(interruption) } else { lifecycle }
    }
    /// The camera lowers its own frame rate under pressure, and with it the film render's cost.
    public private(set) var pressure = CameraPressure.nominal
    public private(set) var capabilities: CameraCapabilities?
    public private(set) var isCapturing = false
    public var acceptsInput: Bool { status == .running && !isCapturing }
    public private(set) var lastCapture: PhotoRecord?
    /// 0…1 of the upright frame, until the reticle fades.
    public private(set) var focusPoint: CGPoint?
    /// For the shutter blink and haptic.
    public private(set) var captureCount = 0
    /// Set it to nil once shown.
    public var error: CameraError?
    /// Filled only while `recordsViewfinderTiming` is on, so a release build doesn't change an
    /// observed property 30 times a second.
    public private(set) var viewfinderTiming = ViewfinderTiming()
    @ObservationIgnored public var recordsViewfinderTiming = false
    /// The look the viewfinder shows and captures start with; a change shows on the next frame.
    public var recipe: Recipe {
        get { settings.recipe }
        set { settings.recipe = newValue }
    }

    /// What the app asked for (`start`, `stop`) and how that went; never `interrupted`.
    private var lifecycle = Status.idle
    private var interruption: CameraInterruption?
    private let source: any CameraSource
    private let store: PhotoStore
    private let settings: AppSettings
    @ObservationIgnored private var hasReportedViewfinderFailure = false
    @ObservationIgnored private var focusReset: Task<Void, Never>?
    @ObservationIgnored var focusIndicatorDuration: Duration = .seconds(1.5)

    public init(source: any CameraSource, store: PhotoStore, settings: AppSettings) {
        self.source = source
        self.store = store
        self.settings = settings
        followEvents()
    }

    /// The stream finishes when the source goes away with the model.
    private func followEvents() {
        let events = source.events()
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                handle(event)
            }
        }
    }

    func handle(_ event: CameraEvent) {
        switch event {
        case .interrupted(let reason):
            // Queued before `stop`: the next start reports a camera that's still taken.
            guard lifecycle == .starting || lifecycle == .running else { return }
            interruption = reason
        case .interruptionEnded: interruption = nil
        case .pressure(let level): if pressure != level { pressure = level }
        case .failed:
            guard lifecycle == .running else { return }
            interruption = nil
            lifecycle = .unavailable
        }
    }

    /// Prepares the renderer while the camera starts, so the first frame doesn't wait for it.
    public func start() async {
        guard lifecycle != .starting, lifecycle != .running else { return }
        lifecycle = .starting
        let renderService = store.renderService
        // A renderer that can't be prepared fails on the first frame instead; the camera still starts.
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
            guard lifecycle == .starting else {
                await source.stop()
                return
            }
            capabilities = started
            lifecycle = .running
        } catch {
            lifecycle = Status(startFailure: error)
            if lifecycle == .unavailable { self.error = error }
        }
    }

    /// Also stops a camera that failed while running, so it can't restart behind the app. A
    /// camera that's still taken reports its interruption again on the next start.
    public func stop() async {
        guard lifecycle == .starting || lifecycle == .running || lifecycle == .unavailable else { return }
        lifecycle = .idle
        interruption = nil
        await source.stop()
    }

    /// Ignored while a photo is being taken, so the capture finishes on the lens it started with.
    public func select(_ lens: CameraLens) async {
        guard acceptsInput, lens != capabilities?.lens else { return }
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

    /// The photo's edit is the recipe shown at the shutter press, whatever happens meanwhile.
    public func capture() async {
        guard acceptsInput, let capabilities else { return }
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

    /// Newest only: while one frame renders, newer ones replace older ones.
    public func viewfinderImages(maxDimension: CGFloat) -> AsyncStream<CGImage> {
        let frames = source.frames()
        let renderService = store.renderService
        let (images, continuation) = AsyncStream.makeStream(of: CGImage.self, bufferingPolicy: .bufferingNewest(1))
        let delivery = Task { [weak self] in
            var frameNumber = 0
            for await frame in frames {
                guard let self else { break }
                let look = viewfinderLook(frameNumber: frameNumber)
                frameNumber += 1
                let started = ContinuousClock.now
                let image: CGImage
                do {
                    image = try await renderService.viewfinderImage(frame, look, maxDimension: maxDimension)
                } catch {
                    reportViewfinderFailure()
                    continue
                }
                if recordsViewfinderTiming {
                    let shown = ContinuousClock.now
                    viewfinderTiming.record(render: started.duration(to: shown), shownAt: shown)
                }
                continuation.yield(image)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in delivery.cancel() }
        return images
    }

    /// Once, so a viewfinder that can't render doesn't stay black without a word.
    private func reportViewfinderFailure() {
        guard !hasReportedViewfinderFailure else { return }
        hasReportedViewfinderFailure = true
        error = .unavailable
    }

    /// Artistic: the grain seed changes every frame so the grain looks alive rather than like a
    /// pattern fixed on the glass.
    func viewfinderLook(frameNumber: Int) -> Adjustments {
        var look = recipe.adjustments
        look.seed = Double(frameNumber % Adjustments.grainSeedCount)
        return look
    }

    public func attachViewfinder(_ layer: ViewfinderLayer) async {
        await source.attachViewfinder(layer)
    }
}
