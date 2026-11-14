#if os(iOS)
    import AVFoundation

    extension AVCameraSource {
        func authorize() async throws(CameraError) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return
            case .notDetermined: if await AVCaptureDevice.requestAccess(for: .video) { return }
            case .restricted: throw .restricted
            default: break
            }
            throw .notAuthorized
        }

        func configure() throws(CameraError) {
            guard !isConfigured else { return }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video,
                position: .back)
            for device in discovery.devices {
                if let lens = CameraLens(device.deviceType) { devices[lens] = device }
            }
            guard !devices.isEmpty else { throw .unavailable }
            lensOptions = LensOption.options(for: devices)

            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .photo
            // The camera's native full-range YCbCr, which Core Image reads directly with its
            // color attachments; BGRA only if a device lacks it.
            let yCbCr = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let format = videoOutput.availableVideoPixelFormatTypes.contains(yCbCr) ? yCbCr : kCVPixelFormatType_32BGRA
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(frameDelivery, queue: frameQueue)
            guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else { throw .unavailable }
            session.addOutput(photoOutput)
            session.addOutput(videoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            isConfigured = true
        }

        /// Swaps the input to `lens` (or the wide lens), then re-applies the RAW formats and
        /// photo sizes, which belong to the device's active format. If the new lens has no RAW
        /// format, the previous input goes back (or none stays, so `start` retries), so `input`,
        /// `lens` and the RAW state always describe what the session runs.
        func use(_ requested: CameraLens) throws(CameraError) {
            let lens = devices[requested] == nil ? .wide : requested
            guard let device = devices[lens] else { throw .unavailable }
            let newInput: AVCaptureDeviceInput
            do { newInput = try AVCaptureDeviceInput(device: device) } catch { throw .unavailable }
            let previous = input
            guard swapInput(from: previous, to: newInput) else { throw .unavailable }
            do {
                try configureRAW(for: device)
            } catch {
                rawPixelFormat = nil
                restore(previous, replacing: newInput)
                throw error
            }
            self.lens = lens
            follow(device)
        }

        /// After a failed switch: the previous input back with its RAW state, or no input at all
        /// (`rawPixelFormat` stays nil), so a later `start` sets the camera up again.
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

        /// On failure the session keeps `old`; `input` is set to whichever the session runs.
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

        /// ProRAW when supported, else Bayer RAW, at the largest size. ProRAW must be enabled
        /// after the input is added, since RAW formats only exist with a video source.
        private func configureRAW(for device: AVCaptureDevice) throws(CameraError) {
            if photoOutput.isAppleProRAWSupported { photoOutput.isAppleProRAWEnabled = true }
            let formats = photoOutput.availableRawPhotoPixelFormatTypes
            let proRAW = formats.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat)
            let bayer = formats.first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat)
            rawFormat = try RAWFormat.preferred(proRAWAvailable: proRAW != nil, bayerAvailable: bayer != nil)
            rawPixelFormat = rawFormat == .proRAW ? proRAW : bayer
            photoDimensions = device.activeFormat.supportedMaxPhotoDimensions.map { PhotoDimensions(width: $0.width, height: $0.height) }
            if let largest = PhotoDimensions.choose(.full, from: photoDimensions) {
                photoOutput.maxPhotoDimensions = CMVideoDimensions(width: largest.width, height: largest.height)
            }
        }
    }
#endif
