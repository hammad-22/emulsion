import Foundation

public struct CameraCapabilities: Sendable, Equatable {
    public let lenses: [LensOption]
    public let lens: CameraLens
    public let rawFormat: RAWFormat
    /// 48 MP as well as 12 MP.
    public let supportsFullResolution: Bool

    public func resolution(for requested: AppSettings.Resolution) -> AppSettings.Resolution {
        supportsFullResolution ? requested : .standard
    }
}
