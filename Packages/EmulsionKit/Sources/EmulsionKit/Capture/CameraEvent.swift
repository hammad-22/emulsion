/// Something that happened to a running camera on its own, not at the app's request.
public enum CameraEvent: Equatable, Sendable {
    /// The system paused the camera; it resumes by itself (`interruptionEnded`).
    case interrupted(CameraInterruption)
    case interruptionEnded
    /// The camera stopped with an error it couldn't recover from; starting it again may work.
    case failed
    /// The device is running hot or short of power (`AVCaptureDevice.systemPressureState`).
    case pressure(CameraPressure)
}

/// Why the system paused the camera (`AVCaptureSession.InterruptionReason`).
public enum CameraInterruption: Equatable, Sendable {
    /// Another app took the camera.
    case inUseByAnotherApp
    /// Another app is on screen beside this one (Stage Manager, iPhone Duo's split screen).
    case multipleForegroundApps
    /// The device is too hot, or short of power, to run the camera.
    case systemPressure
    /// Any other reason: the app moved to the background, a call took the audio.
    case other
}

/// How hard the device is working, from nominal to shutdown (`AVCaptureDevice.SystemPressureState.Level`).
public enum CameraPressure: Int, Comparable, Sendable {
    case nominal, fair, serious, critical, shutdown

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
