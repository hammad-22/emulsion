import CoreGraphics
import Foundation
import Observation

/// The camera screen's state: starts and stops the camera, switches lenses, focuses where
/// the user taps, and adds each capture to the library as an unedited original.
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
    public private(set) var viewfinderTiming = ViewfinderTiming()

    private let source: any CameraSource
    private let store: PhotoStore
    @ObservationIgnored private var focusReset: Task<Void, Never>?
    /// How long the focus reticle stays up after a tap.
    @ObservationIgnored var focusIndicatorDuration: Duration = .seconds(1.5)

    public init(source: any CameraSource, store: PhotoStore) {
        self.source = source
        self.store = store
    }

    /// Starts the camera; does nothing while it's already starting or running.
    public func start() async {
        guard status != .starting, status != .running else { return }
        status = .starting
        do {
            let started = try await source.start(lens: capabilities?.lens ?? .wide)
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

    public func select(_ lens: CameraLens) async {
        guard status == .running, lens != capabilities?.lens else { return }
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

    /// Takes a RAW photo and adds it to the library. Lenses without 48 MP capture at 12 MP.
    public func capture(resolution: AppSettings.Resolution) async {
        guard status == .running, !isCapturing else { return }
        isCapturing = true
        captureCount += 1
        defer { isCapturing = false }
        let supported = capabilities?.supportsFullResolution == true ? resolution : .standard
        let photo: CapturedPhoto
        do {
            photo = try await source.capture(supported)
        } catch {
            self.error = error
            return
        }
        do {
            lastCapture = try await store.add(photo.data, fileExtension: photo.fileExtension)
        } catch {
            self.error = .saveFailed
        }
    }

    /// The viewfinder, each frame rendered off the main actor and fitted within
    /// `maxDimension`. Newest only: while one frame renders, newer ones replace older ones.
    public func viewfinderImages(maxDimension: CGFloat) -> AsyncStream<CGImage> {
        let frames = source.frames()
        let renderService = store.renderService
        let (images, continuation) = AsyncStream.makeStream(of: CGImage.self, bufferingPolicy: .bufferingNewest(1))
        let delivery = Task { [weak self] in
            for await frame in frames {
                let started = ContinuousClock.now
                guard let image = try? await renderService.viewfinderImage(frame, maxDimension: maxDimension) else { continue }
                let shown = ContinuousClock.now
                self?.viewfinderTiming.record(render: started.duration(to: shown), shownAt: shown)
                continuation.yield(image)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in delivery.cancel() }
        return images
    }

    /// The layer the viewfinder draws in, so the camera turns frames upright for it.
    public func attachViewfinder(_ layer: ViewfinderLayer) async {
        await source.attachViewfinder(layer)
    }
}
