#if os(iOS)
    import AVFoundation
    import os

    /// The device's back cameras capturing RAW, following Apple's AVCam sample: an actor
    /// whose executor is the capture session's serial queue, so every session call runs on
    /// that queue.
    ///
    /// Physical cameras only, never a virtual one: Bayer RAW requires a zoom factor of 1
    /// (AVCapturePhotoOutput.h, Bayer RAW rules), and virtual cameras change lenses by zoom.
    public actor AVCameraSource: CameraSource {
        private let sessionQueue = DispatchSerialQueue(label: "com.hammad.emulsion.capture-session")
        let frameQueue = DispatchQueue(label: "com.hammad.emulsion.viewfinder-frames")
        public nonisolated var unownedExecutor: UnownedSerialExecutor { sessionQueue.asUnownedSerialExecutor() }

        let session = AVCaptureSession()
        let photoOutput = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()
        nonisolated let frameDelivery = FrameDelivery()
        nonisolated let eventDelivery = SourceStream.events()
        var isConfigured = false
        var devices: [CameraLens: AVCaptureDevice] = [:]
        var lensOptions: [LensOption] = []
        var input: AVCaptureDeviceInput?
        var lens = CameraLens.wide
        var rawFormat = RAWFormat.proRAW
        var rawPixelFormat: OSType?
        var photoDimensions: [PhotoDimensions] = []
        var viewfinderLayer: ViewfinderLayer?
        var rotation: AVCaptureDevice.RotationCoordinator?
        var rotationObservation: NSKeyValueObservation?
        var pressureObservation: NSKeyValueObservation?
        /// Per device, since a lens keeps its throttled rate while another one runs; a device
        /// not listed runs its format's default.
        var throttledRates: [ObjectIdentifier: Int32] = [:]
        var subjectAreaChanges: Task<Void, Never>?
        var sessionObservers: [any NSObjectProtocol] = []
        let logger = Logger(subsystem: "com.hammad.emulsion", category: "Camera")

        /// The embedded preview's longest side: enough for the editor's "Original" view on a
        /// phone without decoding the RAW.
        private static let thumbnailSize = 2048

        public init() {}

        public nonisolated func frames() -> AsyncStream<CameraFrame> { frameDelivery.stream.makeStream() }

        public nonisolated func events() -> AsyncStream<CameraEvent> { eventDelivery.makeStream() }

        public func start(lens: CameraLens) async throws(CameraError) -> CameraCapabilities {
            try await authorize()
            try configure()
            if input == nil { try use(lens) }
            if subjectAreaChanges == nil { subjectAreaChanges = Task { await self.followSubjectAreaChanges() } }
            if sessionObservers.isEmpty { observeSession() }
            if !session.isRunning { session.startRunning() }
            return capabilities
        }

        public func stop() {
            subjectAreaChanges?.cancel()
            subjectAreaChanges = nil
            for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
            sessionObservers = []
            if session.isRunning { session.stopRunning() }
        }

        public func select(_ lens: CameraLens) throws(CameraError) -> CameraCapabilities {
            try use(lens)
            return capabilities
        }

        public func focusAndExpose(at framePoint: CGPoint) {
            guard let device = input?.device else { return }
            let point = FrameGeometry.devicePoint(forFramePoint: framePoint, rotationAngle: frameDelivery.rotationAngle)
            configure(device) {
                if $0.isFocusPointOfInterestSupported, $0.isFocusModeSupported(.autoFocus) {
                    $0.focusPointOfInterest = point
                    $0.focusMode = .autoFocus
                }
                if $0.isExposurePointOfInterestSupported, $0.isExposureModeSupported(.autoExpose) {
                    $0.exposurePointOfInterest = point
                    $0.exposureMode = .autoExpose
                }
                $0.isSubjectAreaChangeMonitoringEnabled = true
            }
        }

        public func capture(_ resolution: AppSettings.Resolution) async throws(CameraError) -> CapturedPhoto {
            guard session.isRunning, let rawPixelFormat else { throw .captureFailed }
            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawPixelFormat)
            if let size = PhotoDimensions.choose(resolution, from: photoDimensions) {
                settings.maxPhotoDimensions = CMVideoDimensions(width: size.width, height: size.height)
            }
            // Bayer RAW must prioritize speed; ProRAW may use the output's maximum, quality
            // (AVCapturePhotoOutput.h, RAW rules).
            settings.photoQualityPrioritization = rawFormat == .bayer ? .speed : .quality
            if let codec = Self.preferredThumbnailCodec(settings.availableRawEmbeddedThumbnailPhotoCodecTypes) {
                settings.rawEmbeddedThumbnailPhotoFormat = [
                    AVVideoCodecKey: codec, AVVideoWidthKey: Self.thumbnailSize, AVVideoHeightKey: Self.thumbnailSize,
                ]
            }
            if let angle = rotation?.videoRotationAngleForHorizonLevelCapture, let connection = photoOutput.connection(with: .video),
                connection.isVideoRotationAngleSupported(angle)
            {
                connection.videoRotationAngle = angle
            }
            let delegate = PhotoCaptureDelegate()
            let result = await withCheckedContinuation { continuation in
                delegate.deliver(to: continuation)
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
            withExtendedLifetime(delegate) {}
            return CapturedPhoto(data: try result.get(), fileExtension: "dng")
        }

        public func attachViewfinder(_ layer: ViewfinderLayer) {
            viewfinderLayer = layer
            if let device = input?.device { trackRotation(of: device) }
        }

        private var capabilities: CameraCapabilities {
            CameraCapabilities(
                lenses: lensOptions, lens: lens, rawFormat: rawFormat,
                supportsFullResolution: PhotoDimensions.supportsFullResolution(photoDimensions))
        }

        private static func preferredThumbnailCodec(_ available: [AVVideoCodecType]) -> AVVideoCodecType? {
            available.contains(.jpeg) ? .jpeg : available.first
        }
    }
#endif
