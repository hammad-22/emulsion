#if os(iOS)
    import AVFoundation

    extension AVCameraSource {
        func exposure(on device: AVCaptureDevice) -> CameraExposure? {
            let aperture = device.lensAperture
            guard aperture.isFinite, aperture > 0 else { return nil }
            let format = device.activeFormat
            let fastest = format.minExposureDuration.seconds
            let slowest = format.maxExposureDuration.seconds
            let canSetManual =
                device.isExposureModeSupported(.custom) && device.isExposureModeSupported(.continuousAutoExposure)
                && fastest.isFinite && slowest.isFinite && fastest > 0 && fastest <= slowest
                && format.minISO.isFinite && format.maxISO.isFinite && format.minISO > 0 && format.minISO <= format.maxISO
            return CameraExposure(
                isManual: device.exposureMode == .custom, shutterSeconds: device.exposureDuration.seconds,
                iso: device.iso, aperture: aperture,
                shutterStops: canSetManual ? CameraExposure.shutterStops(in: fastest...slowest) : [],
                isoStops: canSetManual ? CameraExposure.isoStops(in: format.minISO...format.maxISO) : [],
                apertureStops: canSetManual ? Self.apertureStops(for: format) : [])
        }

        private static func apertureStops(for format: AVCaptureDevice.Format) -> [Float] {
            guard #available(iOS 27.0, *), format.minLensAperture < format.maxLensAperture else { return [] }
            return format.recommendedLensApertureStops.filter { stop in
                format.supportsExposureModeCustom(
                    lensAperture: stop, duration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO)
            }
        }

        func applyExposure(_ change: CameraExposure.Change, to device: AVCaptureDevice) async throws(CameraError) {
            do { try device.lockForConfiguration() } catch { throw .exposureUnavailable }
            defer { device.unlockForConfiguration() }
            let format = device.activeFormat

            let duration: CMTime
            let iso: Float
            switch change {
            case .automatic:
                try restoreAutomaticExposure(on: device)
                return
            case .shutter(let seconds):
                guard seconds >= format.minExposureDuration.seconds, seconds <= format.maxExposureDuration.seconds
                else { throw .exposureUnavailable }
                let requested = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
                duration = CMTimeMinimum(format.maxExposureDuration, CMTimeMaximum(format.minExposureDuration, requested))
                iso = AVCaptureDevice.currentISO
            case .iso(let value):
                duration = AVCaptureDevice.currentExposureDuration
                guard (format.minISO...format.maxISO).contains(value) else { throw .exposureUnavailable }
                iso = value
            case .aperture(let value):
                guard #available(iOS 27.0, *),
                    format.supportsExposureModeCustom(
                        lensAperture: value, duration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO)
                else { throw .exposureUnavailable }
                _ = await device.setExposureModeCustom(
                    lensAperture: value, duration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO)
                return
            }

            if #available(iOS 27.0, *),
                !format.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: duration, iso: iso)
            {
                throw .exposureUnavailable
            }
            _ = await device.setExposureModeCustom(duration: duration, iso: iso)
        }

        func restoreAutomaticExposure(on device: AVCaptureDevice) throws(CameraError) {
            guard device.isExposureModeSupported(.continuousAutoExposure) else { throw .exposureUnavailable }
            device.exposureMode = .continuousAutoExposure
            let defaultDuration = throttledRates[ObjectIdentifier(device)].map { CMTime(value: 1, timescale: $0) } ?? .invalid
            device.activeVideoMaxFrameDuration = defaultDuration
        }
    }
#endif
