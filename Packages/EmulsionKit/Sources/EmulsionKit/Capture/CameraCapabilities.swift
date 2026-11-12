import Foundation

/// What the running camera offers right now. Changes with the lens.
public struct CameraCapabilities: Sendable, Equatable {
    public let lenses: [LensOption]
    public let lens: CameraLens
    public let rawFormat: RAWFormat
    /// True when this lens can capture at 48 MP as well as 12 MP.
    public let supportsFullResolution: Bool

    /// The resolution a capture gets: lenses without 48 MP capture at 12 MP.
    public func resolution(for requested: AppSettings.Resolution) -> AppSettings.Resolution {
        supportsFullResolution ? requested : .standard
    }
}
