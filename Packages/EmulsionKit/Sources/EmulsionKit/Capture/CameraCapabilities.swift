import Foundation

public struct CameraCapabilities: Sendable, Equatable {
    public let lenses: [LensOption]
    public let lens: CameraLens
    public let zoomFactor: Double
    public let rawFormat: RAWFormat
    public let exposure: CameraExposure?
    /// 48 MP as well as 12 MP.
    public let supportsFullResolution: Bool

    init(
        lenses: [LensOption], lens: CameraLens, zoomFactor: Double = 1, rawFormat: RAWFormat,
        supportsFullResolution: Bool, exposure: CameraExposure? = nil
    ) {
        self.lenses = lenses
        self.lens = lens
        self.zoomFactor = zoomFactor
        self.rawFormat = rawFormat
        self.exposure = exposure
        self.supportsFullResolution = supportsFullResolution
    }

    public func resolution(for requested: AppSettings.Resolution) -> AppSettings.Resolution {
        supportsFullResolution ? requested : .standard
    }
}
