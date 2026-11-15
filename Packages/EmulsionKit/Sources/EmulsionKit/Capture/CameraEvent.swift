public enum CameraEvent: Equatable, Sendable {
    case interrupted(CameraInterruption)
    case interruptionEnded
    case failed
    case pressure(CameraPressure)
}

public enum CameraInterruption: Equatable, Sendable {
    case inUseByAnotherApp
    case multipleForegroundApps
    case systemPressure
    case other
}

public enum CameraPressure: Int, Comparable, Sendable {
    case nominal, fair, serious, critical, shutdown

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
