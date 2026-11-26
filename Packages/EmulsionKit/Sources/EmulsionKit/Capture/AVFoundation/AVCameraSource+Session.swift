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

            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .photo
            // Native full-range YCbCr, which Core Image reads directly; BGRA only if a device lacks it.
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

        func use(_ requested: CameraLens, zoomFactor: Double = 1) throws(CameraError) {
            let lens = devices[requested] == nil ? .wide : requested
            guard let device = devices[lens] else { throw .unavailable }
            if input?.device == device {
                try setZoom(zoomFactor, on: device)
                return
            }
            let newInput: AVCaptureDeviceInput
            do { newInput = try AVCaptureDeviceInput(device: device) } catch { throw .unavailable }
            let previous = input
            guard swapInput(from: previous, to: newInput) else { throw .unavailable }
            do {
                try configureRAW(for: device)
                try setZoom(zoomFactor, on: device)
            } catch {
                rawPixelFormat = nil
                restore(previous, replacing: newInput)
                throw error
            }
            self.lens = lens
            follow(device)
        }

        private func setZoom(_ zoomFactor: Double, on device: AVCaptureDevice) throws(CameraError) {
            let factor = CGFloat(zoomFactor)
            do { try device.lockForConfiguration() } catch { throw .unavailable }
            defer { device.unlockForConfiguration() }
            // AVCapturePhotoOutput requires 1× for Bayer RAW.
            guard factor == 1 || (rawFormat == .proRAW && device.nativeZoomStops.contains(factor)) else { throw .unavailable }
            guard factor != device.videoZoomFactor else { return }
            device.videoZoomFactor = factor
        }

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
            // Frames stay in sensor orientation and carry their rotation (`CameraFrame`).
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            input = new
            return true
        }

        /// ProRAW must be enabled after the input is added: RAW formats need a video source.
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
