import EmulsionCore

/// Negative mired (−10⁶ / kelvin). See Packages/EmulsionKit/NOTES.md, "TemperatureScale".
enum TemperatureScale {
    private static let miredPerInverseKelvin = 1_000_000.0
    /// One ruler tick, in mired: about 150 K at 5500 K, 20 K at 2000 K.
    static let increment = 5.0
    static let range =
        rulerValue(
            kelvin: CameraWhiteBalance.temperatureRange.lowerBound)...rulerValue(kelvin: CameraWhiteBalance.temperatureRange.upperBound)

    static func rulerValue(kelvin: Double) -> Double { -miredPerInverseKelvin / kelvin }
    static func kelvin(rulerValue: Double) -> Double { -miredPerInverseKelvin / rulerValue }
}
