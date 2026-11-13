import Foundation

/// White balance of a RAW develop: the light the camera's neutral is set to, applied in the
/// camera's colour space by Apple's RAW decoder when the file is developed, before the film
/// process. Separate from the printer-light Warmth and Tint, which act at print. Photos that
/// aren't RAW ignore it.
public struct CameraWhiteBalance: Codable, Hashable, Sendable {
    /// Colour temperature, in kelvin, of the light that develops neutral: a higher setting
    /// renders warmer.
    public var temperature: Double
    /// Offset from the Planckian locus: positive renders magenta, negative green.
    public var tint: Double

    /// `CIRAWFilter.neutralTemperature` and `neutralTint` ranges, as Apple documents them in CIRAWFilter.h.
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
