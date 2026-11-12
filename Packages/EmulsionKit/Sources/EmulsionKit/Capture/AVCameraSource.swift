#if os(iOS)
    import AVFoundation
    import Synchronization
    import os

    /// The device's back cameras capturing RAW, following Apple's AVCam sample: an actor
    /// whose executor is the capture session's serial queue, so every session call runs on
    /// that queue.
    ///
    /// Physical cameras only, never a virtual one: Bayer RAW requires a zoom factor of 1
    /// (AVCapturePhotoOutput.h, Bayer RAW rules), and virtual cameras change lenses by zoom.
    public actor AVCameraSource: CameraSource {
        private let sessionQueue = DispatchSerialQueue(label: "com.hammad.emulsion.capture-session")
        private let frameQueue = DispatchQueue(label: "com.hammad.emulsion.viewfinder-frames")
        public nonisolated var unownedExecutor: UnownedSerialExecutor { sessionQueue.asUnownedSerialExecutor() }

        private let session = AVCaptureSession()
        private let photoOutput = AVCapturePhotoOutput()
        private let videoOutput = AVCaptureVideoDataOutput()
        private nonisolated let frameDelivery = FrameDelivery()
        private nonisolated let eventDelivery = SourceStream.events()
        private var isConfigured = false
        private var devices: [CameraLens: AVCaptureDevice] = [:]
        private var lensOptions: [LensOption] = []
        private var input: AVCaptureDeviceInput?
        private var lens = CameraLens.wide
        private var rawFormat = RAWFormat.proRAW
        private var rawPixelFormat: OSType = 0
        private var photoDimensions: [PhotoDimensions] = []
        private var viewfinderLayer: ViewfinderLayer?
        private var rotation: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var pressureObservation: NSKeyValueObservation?
        /// The frame rate each device is held to under pressure; a device not listed runs its
        /// format's default. Per device, since a lens keeps its rate while another one runs.
        private var throttledRates: [ObjectIdentifier: Int32] = [:]
        /// Focus changes, followed while the camera is started.
        private var subjectAreaChanges: Task<Void, Never>?
        /// The session's notifications, observed while the camera is started.
        private var sessionObservers: [any NSObjectProtocol] = []
        private let logger = Logger(subsystem: "com.hammad.emulsion", category: "Camera")

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

        /// Stops the session and what was followed while it ran.
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
            guard session.isRunning, rawPixelFormat != 0 else { throw .captureFailed }
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

        // MARK: Setup

        private func authorize() async throws(CameraError) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return
            case .notDetermined: if await AVCaptureDevice.requestAccess(for: .video) { return }
            case .restricted: throw .restricted
            default: break
            }
            throw .notAuthorized
        }

        private func configure() throws(CameraError) {
            guard !isConfigured else { return }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video,
                position: .back)
            for device in discovery.devices {
                if let lens = CameraLens(device.deviceType) { devices[lens] = device }
            }
            guard !devices.isEmpty else { throw .unavailable }
            lensOptions = Self.lensOptions(devices)

            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .photo
            let formats = videoOutput.availableVideoPixelFormatTypes
            // The camera's native full-range YCbCr, which Core Image reads directly with its
            // color attachments; BGRA only if a device lacks it.
            let yCbCr = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let format = formats.contains(yCbCr) ? yCbCr : kCVPixelFormatType_32BGRA
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(frameDelivery, queue: frameQueue)
            guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else { throw .unavailable }
            session.addOutput(photoOutput)
            session.addOutput(videoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            isConfigured = true
        }

        /// Swaps the input to `lens` (or the wide lens), then re-applies what depends on the
        /// device: RAW formats and photo sizes belong to its active format. If the new lens has
        /// no RAW format, the previous input goes back (or none stays, so `start` retries), and
        /// `input`, `lens` and the RAW state always describe what the session runs.
        private func use(_ requested: CameraLens) throws(CameraError) {
            let lens = devices[requested] == nil ? .wide : requested
            guard let device = devices[lens] else { throw .unavailable }
            let newInput: AVCaptureDeviceInput
            do { newInput = try AVCaptureDeviceInput(device: device) } catch { throw .unavailable }
            let previous = input
            guard swapInput(from: previous, to: newInput) else { throw .unavailable }
            do {
                try configureRAW(for: device)
            } catch {
                rawPixelFormat = 0
                restore(previous, replacing: newInput)
                throw error
            }
            self.lens = lens
            follow(device)
        }

        /// After a failed switch: the previous input back with its RAW state, or no input at all
        /// (`rawPixelFormat` stays 0), so a later `start` sets the camera up again.
        private func restore(_ previous: AVCaptureDeviceInput?, replacing failed: AVCaptureDeviceInput) {
            if let previous, swapInput(from: failed, to: previous), (try? configureRAW(for: previous.device)) != nil {
                follow(previous.device)
                return
            }
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            session.commitConfiguration()
            input = nil
        }

        /// Replaces `old` with `new` in the session; on failure the session keeps `old`. Sets
        /// `input` to whichever the session runs.
        private func swapInput(from old: AVCaptureDeviceInput?, to new: AVCaptureDeviceInput) -> Bool {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            if let old { session.removeInput(old) }
            guard session.canAddInput(new) else {
                if let old { session.addInput(old) }
                input = old
                return false
            }
            session.addInput(new)
            // Frames stay in sensor orientation; each carries the rotation that turns it
            // upright (CameraFrame), so rotating the interface never rebuilds the pipeline.
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            input = new
            return true
        }

        /// ProRAW when supported (it must be enabled after the input is added, since RAW
        /// formats only exist with a video source), else Bayer RAW, at the largest size.
        private func configureRAW(for device: AVCaptureDevice) throws(CameraError) {
            if photoOutput.isAppleProRAWSupported { photoOutput.isAppleProRAWEnabled = true }
            let formats = photoOutput.availableRawPhotoPixelFormatTypes
            let proRAW = formats.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat)
            let bayer = formats.first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat)
            rawFormat = try RAWFormat.preferred(proRAWAvailable: proRAW != nil, bayerAvailable: bayer != nil)
            rawPixelFormat = (rawFormat == .proRAW ? proRAW : bayer) ?? 0
            photoDimensions = device.activeFormat.supportedMaxPhotoDimensions.map { PhotoDimensions(width: $0.width, height: $0.height) }
            if let largest = PhotoDimensions.choose(.full, from: photoDimensions) {
                photoOutput.maxPhotoDimensions = CMVideoDimensions(width: largest.width, height: largest.height)
            }
        }

        /// Follows what belongs to the device the session runs: its rotation and its pressure.
        private func follow(_ device: AVCaptureDevice) {
            trackRotation(of: device)
            pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
                let pressure = CameraPressure(device.systemPressureState.level)
                let deviceID = ObjectIdentifier(device)
                Task { await self?.respond(to: pressure, ofDevice: deviceID) }
            }
        }

        /// Reports the pressure and lowers the frame rate under it, which also lightens the
        /// viewfinder's film render. From `shutdown` the system interrupts the session itself.
        private func respond(to pressure: CameraPressure, ofDevice deviceID: ObjectIdentifier) {
            guard let device = input?.device, ObjectIdentifier(device) == deviceID else { return }
            eventDelivery.yield(.pressure(pressure))
            let rate = Self.frameRate(under: pressure)
            guard rate != throttledRates[deviceID] else { return }
            if let rate,
                !device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                    ($0.minFrameRate...$0.maxFrameRate).contains(Double(rate))
                })
            {
                return
            }
            configure(device) {
                // `.invalid` restores the active format's default rate.
                let duration = rate.map { CMTime(value: 1, timescale: $0) } ?? .invalid
                $0.activeVideoMinFrameDuration = duration
                $0.activeVideoMaxFrameDuration = duration
            }
            throttledRates[deviceID] = rate
        }

        /// 20 fps from `serious`, as Apple's AVCam sample throttled (AVCaptureSystemPressure.h
        /// advises throttling there); half that from `critical`, a judgement to roughly halve the
        /// film render's cost again.
        private static func frameRate(under pressure: CameraPressure) -> Int32? {
            switch pressure {
            case .nominal, .fair: nil
            case .serious: 20
            case .critical, .shutdown: 10
            }
        }

        /// Reports interruptions and runtime errors. Registered before the session starts, since
        /// `startRunning` itself may interrupt it (a camera another app holds). The session
        /// restarts itself after an interruption (AVCaptureSession.h).
        private func observeSession() {
            let center = NotificationCenter.default
            sessionObservers = [
                center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) {
                    [eventDelivery] in eventDelivery.yield(.interrupted(CameraInterruption(reasonIn: $0.userInfo)))
                },
                center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) {
                    [eventDelivery] _ in eventDelivery.yield(.interruptionEnded)
                },
                center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) {
                    [weak self] in
                    let code = ($0.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
                    Task { await self?.recover(from: code) }
                },
            ]
        }

        /// Restarts the session after the media services reset, as Apple's AVCam sample does;
        /// any other runtime error, or a restart that doesn't take, is reported as a failure the
        /// user can retry.
        private func recover(from code: AVError.Code?) {
            logger.error("Capture session runtime error \(code?.rawValue ?? 0)")
            guard !sessionObservers.isEmpty else { return }
            if code == .mediaServicesWereReset, !session.isRunning { session.startRunning() }
            if !session.isRunning { eventDelivery.yield(.failed) }
        }

        private func trackRotation(of device: AVCaptureDevice) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: viewfinderLayer?.layer)
            rotation = coordinator
            // With the viewfinder's layer, the preview angle turns frames upright for the
            // interface orientation the layer is shown in (AVCaptureDevice.h).
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) {
                [frameDelivery] _, change in
                if let angle = change.newValue { frameDelivery.rotationAngle = angle }
            }
        }

        private func followSubjectAreaChanges() async {
            let changes = NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification)
            for await _ in changes.map({ _ in () }) {
                guard let device = input?.device else { continue }
                configure(device) {
                    let center = CGPoint(x: 0.5, y: 0.5)
                    if $0.isFocusPointOfInterestSupported, $0.isFocusModeSupported(.continuousAutoFocus) {
                        $0.focusPointOfInterest = center
                        $0.focusMode = .continuousAutoFocus
                    }
                    if $0.isExposurePointOfInterestSupported, $0.isExposureModeSupported(.continuousAutoExposure) {
                        $0.exposurePointOfInterest = center
                        $0.exposureMode = .continuousAutoExposure
                    }
                    $0.isSubjectAreaChangeMonitoringEnabled = false
                }
            }
        }

        /// Locks the device for one change. A camera that can't be locked (another app holds
        /// it) keeps its current focus and exposure; there's nothing for the user to do.
        private func configure(_ device: AVCaptureDevice, _ change: (AVCaptureDevice) -> Void) {
            do {
                try device.lockForConfiguration()
            } catch {
                logger.error("Couldn't lock the camera for configuration: \(error.localizedDescription)")
                return
            }
            change(device)
            device.unlockForConfiguration()
        }

        private var capabilities: CameraCapabilities {
            CameraCapabilities(
                lenses: lensOptions, lens: lens, rawFormat: rawFormat,
                supportsFullResolution: PhotoDimensions.supportsFullResolution(photoDimensions))
        }

        /// The embedded preview's longest side: enough for the editor's "Original" view on a
        /// phone without decoding the RAW.
        private static let thumbnailSize = 2048

        private static func preferredThumbnailCodec(_ available: [AVVideoCodecType]) -> AVVideoCodecType? {
            available.contains(.jpeg) ? .jpeg : available.first
        }

        /// Each lens's magnification relative to the wide lens, from the 35 mm equivalent
        /// focal lengths (AVCaptureDevice.h, iOS 26), or the field of view if one is unknown.
        private static func lensOptions(_ devices: [CameraLens: AVCaptureDevice]) -> [LensOption] {
            guard let reference = devices[.wide] ?? devices.values.first else { return [] }
            return CameraLens.allCases.compactMap { lens in
                guard let device = devices[lens] else { return nil }
                let focal = Double(device.nominalFocalLengthIn35mmFilm)
                let referenceFocal = Double(reference.nominalFocalLengthIn35mmFilm)
                if focal > 0, referenceFocal > 0 { return LensOption(lens: lens, magnification: focal / referenceFocal) }
                let halfAngle = { (device: AVCaptureDevice) in Double(device.activeFormat.videoFieldOfView) * .pi / 360 }
                return LensOption(lens: lens, magnification: tan(halfAngle(reference)) / tan(halfAngle(device)))
            }
        }
    }

    extension CameraInterruption {
        fileprivate init(reasonIn userInfo: [AnyHashable: Any]?) {
            let code = userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            switch code.flatMap(AVCaptureSession.InterruptionReason.init) {
            case .videoDeviceInUseByAnotherClient: self = .inUseByAnotherApp
            case .videoDeviceNotAvailableWithMultipleForegroundApps: self = .multipleForegroundApps
            case .videoDeviceNotAvailableDueToSystemPressure: self = .systemPressure
            default: self = .other
            }
        }
    }

    extension CameraPressure {
        fileprivate init(_ level: AVCaptureDevice.SystemPressureState.Level) {
            switch level {
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            case .shutdown: self = .shutdown
            default: self = .nominal
            }
        }
    }

    extension CameraLens {
        fileprivate init?(_ type: AVCaptureDevice.DeviceType) {
            switch type {
            case .builtInUltraWideCamera: self = .ultraWide
            case .builtInWideAngleCamera: self = .wide
            case .builtInTelephotoCamera: self = .telephoto
            default: return nil
            }
        }
    }

    /// Receives viewfinder frames on the frame queue and passes the newest on, with the
    /// rotation that turns it upright.
    private final class FrameDelivery: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
        let stream = SourceStream.frames()
        private let angle = Mutex<Double>(0)

        var rotationAngle: Double {
            get { angle.withLock { $0 } }
            set { angle.withLock { $0 = newValue } }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let buffer = sampleBuffer.imageBuffer else { return }
            stream.yield(CameraFrame(pixelBuffer: buffer, rotationAngle: rotationAngle))
        }
    }

    /// Turns one photo capture's delegate callbacks into a single result.
    private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
        private struct State {
            var continuation: CheckedContinuation<Result<Data, CameraError>, Never>?
            var data: Data?
        }
        private let state = Mutex(State())

        func deliver(to continuation: CheckedContinuation<Result<Data, CameraError>, Never>) {
            state.withLock { $0.continuation = continuation }
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
            let data = error == nil ? photo.fileDataRepresentation() : nil
            state.withLock { $0.data = data }
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?
        ) {
            let (continuation, data) = state.withLock { state in
                defer { state.continuation = nil }
                return (state.continuation, state.data)
            }
            continuation?.resume(returning: data.map(Result.success) ?? .failure(.captureFailed))
        }
    }
#endif
