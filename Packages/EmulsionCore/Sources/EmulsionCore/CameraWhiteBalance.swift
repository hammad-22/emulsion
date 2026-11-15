import Foundation

/// White balance applied by Apple's RAW decoder at develop, before the film process.
public struct CameraWhiteBalance: Codable, Hashable, Sendable {
    /// Kelvin of the light that develops neutral: a higher setting renders warmer.
    public var temperature: Double
    /// Offset from the Planckian locus: positive renders magenta, negative green.
    public var tint: Double

    /// `CIRAWFilter.neutralTemperature` and `neutralTint` ranges, sourced from CIRAWFilter.h.
    public static let temperatureRange = 2000.0...50000.0
    public static let tintRange = -150.0...150.0

    public init(temperature: Double, tint: Double) {
        self.temperature = temperature
        self.tint = tint
    }

    public func clamped() -> CameraWhiteBalance {
        CameraWhiteBalance(
            temperature: min(max(temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound),
            tint: min(max(tint, Self.tintRange.lowerBound), Self.tintRange.upperBound))
    }
}
