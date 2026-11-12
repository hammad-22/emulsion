import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// A stand-in camera for the Simulator (which has none) and tests: the bundled sample
/// photos as a live viewfinder, drifting slowly so it visibly moves, one sample per lens.
/// Capture returns the sample's JPEG: there's no DNG to bundle, since the samples are
/// synthetic renders, not camera files. Frames are drawn on the CPU, so the stand-in makes no
/// GPU context of its own: the renderer's stays the only one (MOV-127).
public actor MockCameraSource: CameraSource {
    /// Portrait 3:4, like a phone camera's viewfinder held upright.
    static let frameSize = CGSize(width: 768, height: 1024)
    /// About 30 frames per second, the camera's viewfinder rate.
    private static let frameInterval: Duration = .milliseconds(33)
    /// Artistic: how far the crop pans across a sample, and how long one sweep takes.
    private static let drift = (pan: 0.25, period: 8.0)

    private let authorized: Bool
    private let captureError: CameraError?
    private let lenses: [LensOption]
    private let captureGate: CaptureGate?
    private nonisolated let stream = FrameStream()
    private var lens = CameraLens.wide
    private var delivery: Task<Void, Never>?
    /// Each sample scaled once to cover the frame with room to pan.
    private var samples: [CGImage] = []

    /// The last focus point and capture resolution asked for; for tests.
    private(set) var lastFocusPoint: CGPoint?
    private(set) var lastCaptureResolution: AppSettings.Resolution?

    private static let defaultLenses = [
        LensOption(lens: .ultraWide, magnification: 0.5), LensOption(lens: .wide, magnification: 1),
        LensOption(lens: .telephoto, magnification: 4),
    ]

    public init() {
        self.init(authorized: true)
    }

    init(
        authorized: Bool = true, captureError: CameraError? = nil, lenses: [LensOption] = defaultLenses,
        captureGate: CaptureGate? = nil
    ) {
        self.authorized = authorized
        self.captureError = captureError
        self.lenses = lenses
        self.captureGate = captureGate
    }

    /// For tests: a capture says it has started, then waits until released, so a test can act
    /// while the shutter is in flight.
    struct CaptureGate {
        let started: AsyncStream<Void>.Continuation
        let release: AsyncStream<Void>
    }

    public nonisolated func frames() -> AsyncStream<CameraFrame> { stream.makeStream() }

    public func start(lens: CameraLens) throws(CameraError) -> CameraCapabilities {
        guard authorized else { throw .notAuthorized }
        guard !lenses.isEmpty else { throw .unavailable }
        if samples.isEmpty { samples = PhotoStore.sampleURLs.compactMap(Self.panningSample) }
        self.lens = lenses.contains { $0.lens == lens } ? lens : lenses[0].lens
        if delivery == nil { delivery = Task { await deliverFrames() } }
        return capabilities
    }

    public func stop() {
        delivery?.cancel()
        delivery = nil
    }

    public func select(_ lens: CameraLens) throws(CameraError) -> CameraCapabilities {
        guard lenses.contains(where: { $0.lens == lens }) else { throw .unavailable }
        self.lens = lens
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
        CameraCapabilities(lenses: lenses, lens: lens, rawFormat: .proRAW, supportsFullResolution: lens != .ultraWide)
    }

    private var sampleIndex: Int { lenses.firstIndex { $0.lens == lens } ?? 0 }

    private var sampleURL: URL? {
        let urls = PhotoStore.sampleURLs
        return urls.isEmpty ? nil : urls[sampleIndex % urls.count]
    }

    private func deliverFrames() async {
        let start = ContinuousClock.now
        while !Task.isCancelled {
            if let next = frame(at: start.duration(to: .now) / .seconds(1)) { stream.yield(next) }
            try? await Task.sleep(for: Self.frameInterval)
        }
    }

    /// A portrait crop of the lens's sample, panning back and forth: the frame `seconds` into
    /// the pan.
    func frame(at seconds: Double) -> CameraFrame? {
        guard !samples.isEmpty else { return nil }
        let sample = samples[sampleIndex % samples.count]
        let room = CGSize(width: CGFloat(sample.width) - Self.frameSize.width, height: CGFloat(sample.height) - Self.frameSize.height)
        let travel = room.width * (0.5 + 0.5 * sin(seconds * 2 * .pi / Self.drift.period))
        // Whole pixels, inside the sample, so every frame is exactly `frameSize`.
        let origin = CGPoint(x: min(max(travel.rounded(), 0), room.width), y: min(max((room.height / 2).rounded(), 0), room.height))
        let crop = CGRect(origin: origin, size: Self.frameSize)
        return sample.cropping(to: crop).flatMap(CameraFrame.init(drawing:))
    }

    /// A bundled sample decoded and scaled, once, to cover the frame plus the pan.
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
