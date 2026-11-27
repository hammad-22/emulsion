import Foundation

public struct CameraCapabilities: Sendable, Equatable {
    public let lenses: [LensOption]
    public let lens: CameraLens
    public let zoomFactor: Double
    public let rawFormat: RAWFormat
    /// 48 MP as well as 12 MP.
    public let supportsFullResolution: Bool

    init(lenses: [LensOption], lens: CameraLens, zoomFactor: Double = 1, rawFormat: RAWFormat, supportsFullResolution: Bool) {
        self.lenses = lenses
        self.lens = lens
        self.zoomFactor = zoomFactor
        self.rawFormat = rawFormat
        self.supportsFullResolution = supportsFullResolution
    }

    public func resolution(for requested: AppSettings.Resolution) -> AppSettings.Resolution {
        supportsFullResolution ? requested : .standard
    }
}
