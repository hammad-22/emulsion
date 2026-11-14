#if os(iOS)
    import AVFoundation
    import os

    extension AVCameraSource {
        private static let frameCenter = CGPoint(x: 0.5, y: 0.5)

        func follow(_ device: AVCaptureDevice) {
            trackRotation(of: device)
            pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
                let pressure = CameraPressure(device.systemPressureState.level)
                let deviceID = ObjectIdentifier(device)
                Task { await self?.respond(to: pressure, ofDevice: deviceID) }
            }
        }

        /// Lowering the frame rate also lightens the viewfinder's film render. From `shutdown`
        /// the system interrupts the session itself.
        private func respond(to pressure: CameraPressure, ofDevice deviceID: ObjectIdentifier) {
            guard let device = input?.device, ObjectIdentifier(device) == deviceID else { return }
            eventDelivery.yield(.pressure(pressure))
            let rate = pressure.throttledFrameRate
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

        /// Registered before the session starts, since `startRunning` itself may interrupt it (a
        /// camera another app holds). The session restarts itself after an interruption
        /// (AVCaptureSession.h).
        func observeSession() {
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

        func trackRotation(of device: AVCaptureDevice) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: viewfinderLayer?.layer)
            rotation = coordinator
            // With the viewfinder's layer, the preview angle turns frames upright for the
            // interface orientation the layer is shown in (AVCaptureDevice.h).
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) {
                [frameDelivery] _, change in
                if let angle = change.newValue { frameDelivery.rotationAngle = angle }
            }
        }

        func followSubjectAreaChanges() async {
            let changes = NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification)
            for await _ in changes.map({ _ in () }) {
                guard let device = input?.device else { continue }
                configure(device) {
                    if $0.isFocusPointOfInterestSupported, $0.isFocusModeSupported(.continuousAutoFocus) {
                        $0.focusPointOfInterest = Self.frameCenter
                        $0.focusMode = .continuousAutoFocus
                    }
                    if $0.isExposurePointOfInterestSupported, $0.isExposureModeSupported(.continuousAutoExposure) {
                        $0.exposurePointOfInterest = Self.frameCenter
                        $0.exposureMode = .continuousAutoExposure
                    }
                    $0.isSubjectAreaChangeMonitoringEnabled = false
                }
            }
        }

        /// A camera that can't be locked (another app holds it) keeps its current focus and
        /// exposure; there's nothing for the user to do.
        func configure(_ device: AVCaptureDevice, _ change: (AVCaptureDevice) -> Void) {
            do {
                try device.lockForConfiguration()
            } catch {
                logger.error("Couldn't lock the camera for configuration: \(error.localizedDescription)")
                return
            }
            change(device)
            device.unlockForConfiguration()
        }
    }
#endif
