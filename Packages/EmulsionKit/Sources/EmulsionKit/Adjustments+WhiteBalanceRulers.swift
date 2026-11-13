import EmulsionCore

/// The RAW white balance as two ruler values that rest at the photo's as-shot white balance.
/// Subscripts, so a key path can carry the as-shot value (`AdjustmentGroup.controls`).
extension Adjustments {
    /// Each ruler's value within this of as shot counts as as shot: a tenth of a ruler tick,
    /// far below a visible change, and above the rounding of a kelvin ↔ mired round trip.
    static let asShotTolerance = (temperature: TemperatureScale.increment / 10, tint: AdjustmentGroup.whiteBalanceTintIncrement / 10)

    /// Temperature on the ruler's scale (`TemperatureScale`).
    subscript(temperatureAsShot asShot: CameraWhiteBalance) -> Double {
        get { TemperatureScale.rulerValue(kelvin: (whiteBalance ?? asShot).temperature) }
        set {
            setWhiteBalance(temperature: TemperatureScale.kelvin(rulerValue: newValue), tint: (whiteBalance ?? asShot).tint, asShot: asShot)
        }
    }

    /// Tint in Apple's units: positive renders magenta, negative green.
    subscript(tintAsShot asShot: CameraWhiteBalance) -> Double {
        get { (whiteBalance ?? asShot).tint }
        set { setWhiteBalance(temperature: (whiteBalance ?? asShot).temperature, tint: newValue, asShot: asShot) }
    }

    /// Back at the as-shot values the white balance is nil again, so the photo doesn't count as
    /// edited and develops exactly as shot.
    private mutating func setWhiteBalance(temperature: Double, tint: Double, asShot: CameraWhiteBalance) {
        let temperatureOffset = TemperatureScale.rulerValue(kelvin: temperature) - TemperatureScale.rulerValue(kelvin: asShot.temperature)
        let isAsShot = abs(temperatureOffset) <= Self.asShotTolerance.temperature && abs(tint - asShot.tint) <= Self.asShotTolerance.tint
        whiteBalance = isAsShot ? nil : CameraWhiteBalance(temperature: temperature, tint: tint)
    }
}

/// The Temperature ruler's scale: negative mired (−10⁶ / kelvin). Equal steps in mired are
/// roughly equal visible steps at any temperature, where equal steps in kelvin are coarse at
/// tungsten and imperceptible at shade; negated so the ruler increases with the kelvin setting,
/// which renders warmer, the way Warmth does.
enum TemperatureScale {
    private static let kelvinMired = 1_000_000.0
    /// One ruler tick, in mired: about 150 K at daylight (5500 K), 20 K at 2000 K.
    static let increment = 5.0
    static let range =
        rulerValue(
            kelvin: CameraWhiteBalance.temperatureRange.lowerBound)...rulerValue(kelvin: CameraWhiteBalance.temperatureRange.upperBound)

    static func rulerValue(kelvin: Double) -> Double { -kelvinMired / kelvin }
    static func kelvin(rulerValue: Double) -> Double { -kelvinMired / rulerValue }
}
