import CoreImage
import CoreVideo
import Foundation

/// A stand-in camera for the Simulator (which has none) and tests: the bundled sample
/// photos as a live viewfinder, drifting slowly so it visibly moves, one sample per lens.
/// Capture returns the sample's JPEG: there's no DNG to bundle, since the samples are
/// synthetic renders, not camera files.
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
    private nonisolated let stream = FrameStream()
    private var lens = CameraLens.wide
    private var delivery: Task<Void, Never>?
    private var samples: [CIImage] = []
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?

    /// The last focus point and capture resolution asked for; for tests.
    private(set) var lastFocusPoint: CGPoint?
    private(set) var lastCaptureResolution: AppSettings.Resolution?

    public static let defaultLenses = [
        LensOption(lens: .ultraWide, magnification: 0.5), LensOption(lens: .wide, magnification: 1),
        LensOption(lens: .telephoto, magnification: 4),
    ]

    public init(authorized: Bool = true, captureError: CameraError? = nil, lenses: [LensOption] = defaultLenses) {
        self.authorized = authorized
        self.captureError = captureError
        self.lenses = lenses
    }

    public nonisolated func frames() -> AsyncStream<CameraFrame> { stream.makeStream() }

    public func start(lens: CameraLens) throws(CameraError) -> CameraCapabilities {
        guard authorized else { throw .notAuthorized }
        guard !lenses.isEmpty else { throw .unavailable }
        if samples.isEmpty { samples = PhotoStore.sampleURLs.compactMap { CIImage(contentsOf: $0) } }
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

    public func capture(_ resolution: AppSettings.Resolution) throws(CameraError) -> CapturedPhoto {
        lastCaptureResolution = resolution
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
            if let frame = makeFrame(at: start.duration(to: .now) / .seconds(1)) { stream.yield(frame) }
            try? await Task.sleep(for: Self.frameInterval)
        }
    }

    /// A portrait crop of the lens's sample, panning back and forth, rendered into a BGRA
    /// buffer tagged sRGB like a camera frame tagged with its color space.
    private func makeFrame(at seconds: Double) -> CameraFrame? {
        guard !samples.isEmpty, let buffer = makeBuffer() else { return nil }
        let sample = samples[sampleIndex % samples.count]
        let extent = sample.extent
        let scale = max(Self.frameSize.width / extent.width, Self.frameSize.height / extent.height) * (1 + Self.drift.pan)
        let scaled = sample.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let travel = (scaled.extent.width - Self.frameSize.width) * (0.5 + 0.5 * sin(seconds * 2 * .pi / Self.drift.period))
        let centered = (scaled.extent.height - Self.frameSize.height) / 2
        let crop = scaled.transformed(by: CGAffineTransform(translationX: -travel, y: -centered))
        context.render(crop, to: buffer, bounds: CGRect(origin: .zero, size: Self.frameSize), colorSpace: Self.sRGB)
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, Self.sRGB, .shouldPropagate)
        return CameraFrame(pixelBuffer: buffer)
    }

    private func makeBuffer() -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(Self.frameSize.width), kCVPixelBufferHeightKey: Int(Self.frameSize.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
}
