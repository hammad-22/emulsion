import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// A stand-in camera for the Simulator and tests. See Packages/EmulsionKit/NOTES.md, "MockCameraSource".
public actor MockCameraSource: CameraSource {
    static let frameSize = CGSize(width: 768, height: 1024)
    /// About 30 fps, the camera's viewfinder rate.
    private static let frameInterval: Duration = .milliseconds(33)
    /// Artistic: the fraction of a sample the crop pans across, and one sweep in seconds.
    private static let drift = (pan: 0.25, period: 8.0)

    private let startError: CameraError?
    private let captureError: CameraError?
    private let lenses: [LensOption]
    private let captureGate: CaptureGate?
    private nonisolated let stream = SourceStream.frames()
    private nonisolated let eventStream = SourceStream.events()
    private var lens = CameraLens.wide
    private var zoomFactor = 1.0
    private var delivery: Task<Void, Never>?
    private var isInterrupted = false
    private var samples: [CGImage] = []

    var isRunning: Bool { delivery != nil }
    private(set) var lastFocusPoint: CGPoint?
    private(set) var lastCaptureResolution: AppSettings.Resolution?

    private static let defaultLenses = [
        LensOption(lens: .ultraWide, magnification: 0.5), LensOption(lens: .wide, magnification: 1),
        LensOption(lens: .telephoto, magnification: 4),
    ]

    public init() {
        self.init(startError: nil)
    }

    public init(failingStartWith error: CameraError) {
        self.init(startError: error)
    }

    init(
        startError: CameraError? = nil, captureError: CameraError? = nil, lenses: [LensOption] = defaultLenses,
        captureGate: CaptureGate? = nil
    ) {
        self.startError = startError
        self.captureError = captureError
        self.lenses = lenses
        self.captureGate = captureGate
    }

    struct CaptureGate {
        let started: AsyncStream<Void>.Continuation
        let release: AsyncStream<Void>
    }

    public nonisolated func frames() -> AsyncStream<CameraFrame> { stream.makeStream() }

    public nonisolated func events() -> AsyncStream<CameraEvent> { eventStream.makeStream() }

    public func emit(_ event: CameraEvent) {
        switch event {
        case .interrupted: isInterrupted = true
        case .interruptionEnded: isInterrupted = false
        case .failed, .pressure: break
        }
        eventStream.yield(event)
    }

    public func start(lens: CameraLens) throws(CameraError) -> CameraCapabilities {
        if let startError { throw startError }
        guard !lenses.isEmpty else { throw .unavailable }
        if samples.isEmpty { samples = PhotoStore.sampleURLs.compactMap(Self.panningSample) }
        if self.lens != lens || !lenses.contains(where: { $0.lens == lens }) {
            self.lens = lenses.contains { $0.lens == lens } ? lens : lenses[0].lens
            zoomFactor = 1
        }
        if delivery == nil { delivery = Task { await deliverFrames() } }
        return capabilities
    }

    public func stop() {
        delivery?.cancel()
        delivery = nil
        isInterrupted = false
    }

    public func select(_ lens: CameraLens, zoomFactor: Double) throws(CameraError) -> CameraCapabilities {
        guard lenses.contains(where: { $0.lens == lens && $0.zoomFactor == zoomFactor }) else { throw .unavailable }
        self.lens = lens
        self.zoomFactor = zoomFactor
        return capabilities
    }

    public func focusAndExpose(at framePoint: CGPoint) {
        lastFocusPoint = framePoint
    }

    public func capture(_ resolution: AppSettings.Resolution) async throws(CameraError) -> CapturedPhoto {
        lastCaptureResolution = resolution
        if let captureGate {
            captureGate.started.yield()
            for await _ in captureGate.release { break }
        }
        if let captureError { throw captureError }
        guard let url = sampleURL, let data = try? Data(contentsOf: url) else { throw .captureFailed }
        return CapturedPhoto(data: data, fileExtension: url.pathExtension)
    }

    public func attachViewfinder(_ layer: ViewfinderLayer) {}

    private var capabilities: CameraCapabilities {
        CameraCapabilities(
            lenses: lenses, lens: lens, zoomFactor: zoomFactor, rawFormat: .proRAW,
            supportsFullResolution: lens != .ultraWide && zoomFactor == 1)
    }

    private var sampleIndex: Int { lenses.filter { $0.zoomFactor == 1 }.firstIndex { $0.lens == lens } ?? 0 }

    private var sampleURL: URL? {
        let urls = PhotoStore.sampleURLs
        return urls.isEmpty ? nil : urls[sampleIndex % urls.count]
    }

    private func deliverFrames() async {
        let start = ContinuousClock.now
        while !Task.isCancelled {
            if !isInterrupted, let next = frame(at: start.duration(to: .now) / .seconds(1)) { stream.yield(next) }
            try? await Task.sleep(for: Self.frameInterval)
        }
    }

    func frame(at seconds: Double) -> CameraFrame? {
        guard !samples.isEmpty else { return nil }
        let sample = samples[sampleIndex % samples.count]
        let room = CGSize(width: CGFloat(sample.width) - Self.frameSize.width, height: CGFloat(sample.height) - Self.frameSize.height)
        let travel = room.width * (0.5 + 0.5 * sin(seconds * 2 * .pi / Self.drift.period))
        let origin = CGPoint(x: min(max(travel.rounded(), 0), room.width), y: min(max((room.height / 2).rounded(), 0), room.height))
        let crop = CGRect(origin: origin, size: Self.frameSize)
        return sample.cropping(to: crop).flatMap(CameraFrame.init(drawing:))
    }

    private static func panningSample(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let scale = max(frameSize.width / CGFloat(image.width), frameSize.height / CGFloat(image.height)) * (1 + drift.pan)
        let width = Int((CGFloat(image.width) * scale).rounded(.up))
        let height = Int((CGFloat(image.height) * scale).rounded(.up))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CameraFrame.sRGB,
                bitmapInfo: CameraFrame.bgra)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
