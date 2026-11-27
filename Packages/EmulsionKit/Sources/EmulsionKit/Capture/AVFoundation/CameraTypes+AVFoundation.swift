#if os(iOS)
    import AVFoundation

    extension CameraInterruption {
        init(reasonIn userInfo: [AnyHashable: Any]?) {
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
        init(_ level: AVCaptureDevice.SystemPressureState.Level) {
            switch level {
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            case .shutdown: self = .shutdown
            default: self = .nominal
            }
        }

        /// 20 fps from `serious` (AVCam sample), 10 from `critical` (artistic). See Packages/EmulsionKit/NOTES.md.
        var throttledFrameRate: Int32? {
            switch self {
            case .nominal, .fair: nil
            case .serious: 20
            case .critical, .shutdown: 10
            }
        }
    }

    extension CameraLens {
        init?(_ type: AVCaptureDevice.DeviceType) {
            switch type {
            case .builtInUltraWideCamera: self = .ultraWide
            case .builtInWideAngleCamera: self = .wide
            case .builtInTelephotoCamera: self = .telephoto
            default: return nil
            }
        }
    }

    extension LensOption {
        /// From 35 mm equivalent focal lengths, else the field of view (AVCaptureDevice.h).
        static func options(for devices: [CameraLens: AVCaptureDevice], nativeZoom: [CameraLens: [CGFloat]]) -> [LensOption] {
            guard let reference = devices[.wide] ?? devices.values.first else { return [] }
            let physical: [LensOption] = CameraLens.allCases.compactMap { lens in
                guard let device = devices[lens] else { return nil }
                let focal = Double(device.nominalFocalLengthIn35mmFilm)
                let referenceFocal = Double(reference.nominalFocalLengthIn35mmFilm)
                if focal > 0, referenceFocal > 0 { return LensOption(lens: lens, magnification: focal / referenceFocal) }
                let halfAngle = { (device: AVCaptureDevice) in Double(device.activeFormat.videoFieldOfView) * .pi / 360 }
                return LensOption(lens: lens, magnification: tan(halfAngle(reference)) / tan(halfAngle(device)))
            }
            let native = physical.flatMap { base in
                (nativeZoom[base.lens] ?? []).map { factor in
                    LensOption(lens: base.lens, magnification: base.magnification * Double(factor), zoomFactor: Double(factor))
                }
            }
            return LensOption.merging(physical: physical, native: native)
        }
    }

    extension AVCaptureDevice {
        var nativeZoomStops: [CGFloat] {
            activeFormat.secondaryNativeResolutionZoomFactors.filter {
                $0 > 1 && $0 >= minAvailableVideoZoomFactor && $0 <= maxAvailableVideoZoomFactor
            }
        }
    }
#endif
