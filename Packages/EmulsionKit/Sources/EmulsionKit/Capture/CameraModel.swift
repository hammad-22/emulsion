import CoreGraphics
import EmulsionCore
import Foundation
import Observation

/// The camera screen's state. See Packages/EmulsionKit/NOTES.md, "CameraModel".
@MainActor @Observable
public final class CameraModel {
    public enum Status: Equatable, Sendable {
        case idle, starting, running, unauthorized, restricted, unavailable
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
    public private(set) var pressure = CameraPressure.nominal
    public private(set) var capabilities: CameraCapabilities?
    public private(set) var isCapturing = false
    private var isSelectingLens = false
    public var acceptsInput: Bool { status == .running && !isCapturing && !isSelectingLens }
    public private(set) var lastCapture: PhotoRecord?
    /// 0…1 of the upright frame, until the reticle fades.
    public private(set) var focusPoint: CGPoint?
    public private(set) var captureCount = 0
    /// Set it to nil once shown.
    public var error: CameraError?
    /// Filled only while `recordsViewfinderTiming` is on, sparing release builds 30 changes a second.
    public private(set) var viewfinderTiming = ViewfinderTiming()
    @ObservationIgnored public var recordsViewfinderTiming = false
    public var recipe: Recipe {
        get { settings.recipe }
        set { settings.recipe = newValue }
    }

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

    public func stop() async {
        guard lifecycle == .starting || lifecycle == .running || lifecycle == .unavailable else { return }
        lifecycle = .idle
        interruption = nil
        await source.stop()
    }

    public func select(_ lens: CameraLens, zoomFactor: Double = 1) async {
        guard acceptsInput, let current = capabilities,
            lens != current.lens || zoomFactor != current.zoomFactor
        else { return }
        isSelectingLens = true
        defer { isSelectingLens = false }
        do {
            capabilities = try await source.select(lens, zoomFactor: zoomFactor)
        } catch {
            self.error = error
        }
    }

    /// `point` is 0…1 of the upright frame, top-left origin.
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

    private func reportViewfinderFailure() {
        guard !hasReportedViewfinderFailure else { return }
        hasReportedViewfinderFailure = true
        error = .unavailable
    }

    /// Artistic: a new grain seed every frame, so grain looks alive rather than fixed on the glass.
    func viewfinderLook(frameNumber: Int) -> Adjustments {
        var look = recipe.adjustments
        look.seed = Double(frameNumber % Adjustments.grainSeedCount)
        return look
    }

    public func attachViewfinder(_ layer: ViewfinderLayer) async {
        await source.attachViewfinder(layer)
    }
}
