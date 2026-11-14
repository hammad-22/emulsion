import EmulsionCore

/// The Temperature ruler's scale: negative mired (−10⁶ / kelvin). Equal steps in mired are
/// roughly equal visible steps at any temperature, where equal steps in kelvin are coarse at
/// tungsten and imperceptible at shade; negated so the ruler increases with the kelvin setting,
/// which renders warmer, the way Warmth does.
enum TemperatureScale {
    private static let miredPerInverseKelvin = 1_000_000.0
    /// One ruler tick, in mired: about 150 K at daylight (5500 K), 20 K at 2000 K.
    static let increment = 5.0
    static let range =
        rulerValue(
            kelvin: CameraWhiteBalance.temperatureRange.lowerBound)...rulerValue(kelvin: CameraWhiteBalance.temperatureRange.upperBound)

    static func rulerValue(kelvin: Double) -> Double { -miredPerInverseKelvin / kelvin }
    static func kelvin(rulerValue: Double) -> Double { -miredPerInverseKelvin / rulerValue }
}
