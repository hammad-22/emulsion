import EmulsionCore
import Foundation

/// The editor's controls, grouped the way the film process is: exposure and local tone, the
/// RAW develop's white balance, printer lights and color density, then texture. Shared so iOS
/// and Mac show the same controls with the same ranges; the iPhone panel shows one group at a time.
public enum AdjustmentGroup: String, CaseIterable, Identifiable, Sendable {
    case light, whiteBalance, color, texture

    public var id: Self { self }

    /// The ranges `Adjustments.clamped()` enforces before rendering; a test keeps them in step.
    static let exposureRange: ClosedRange<Double> = -3...3
    static let balanceRange: ClosedRange<Double> = -1...1
    static let amountRange: ClosedRange<Double> = 0...1
    /// One ruler tick of white balance tint, in Apple's units (−150…150).
    static let whiteBalanceTintIncrement = 2.0

    /// The groups a photo has: white balance only for a RAW photo, once its as-shot white
    /// balance (where the rulers rest) is known.
    public static func available(whiteBalanceAsShot asShot: CameraWhiteBalance?) -> [AdjustmentGroup] {
        allCases.filter { $0 != .whiteBalance || asShot != nil }
    }

    public var title: String {
        switch self {
        case .light: String(localized: "Light", bundle: .module)
        case .whiteBalance: String(localized: "White Balance", bundle: .module)
        case .color: String(localized: "Color", bundle: .module)
        case .texture: String(localized: "Texture", bundle: .module)
        }
    }

    /// The one control whose value differs between two edits, or nil when none or several
    /// do (Reset Edits): a ruler move changes exactly one.
    public static func changedControl(
        from old: Adjustments, to new: Adjustments, whiteBalanceAsShot asShot: CameraWhiteBalance?
    ) -> (group: AdjustmentGroup, control: AdjustmentControl.ID)? {
        let changed = allCases.flatMap { group in
            group.controls(whiteBalanceAsShot: asShot)
                .filter { old[keyPath: $0.keyPath] != new[keyPath: $0.keyPath] }.map { (group: group, control: $0.id) }
        }
        return changed.count == 1 ? changed[0] : nil
    }

    /// The group's controls. White balance has none without the photo's as-shot white balance.
    public func controls(whiteBalanceAsShot asShot: CameraWhiteBalance?) -> [AdjustmentControl] {
        switch self {
        case .whiteBalance:
            guard let asShot = asShot?.clamped() else { return [] }
            return [
                .init(
                    title: String(localized: "Temperature", bundle: .module), keyPath: \.[temperatureAsShot: asShot],
                    range: TemperatureScale.range, unit: .temperature),
                .init(
                    title: String(localized: "Tint", bundle: .module, comment: "White balance tint, green to magenta"),
                    accessibilityLabel: String(localized: "White Balance Tint", bundle: .module),
                    keyPath: \.[tintAsShot: asShot], range: CameraWhiteBalance.tintRange, unit: .whiteBalanceTint),
            ]
        case .light:
            return [
                .init(title: String(localized: "Exposure", bundle: .module), keyPath: \.exposure, range: Self.exposureRange, unit: .stops),
                .init(title: String(localized: "Highlights", bundle: .module), keyPath: \.highlights, range: Self.balanceRange),
                .init(title: String(localized: "Shadows", bundle: .module), keyPath: \.shadows, range: Self.balanceRange),
            ]
        case .color:
            return [
                .init(title: String(localized: "Warmth", bundle: .module), keyPath: \.warmth, range: Self.balanceRange),
                .init(title: String(localized: "Tint", bundle: .module), keyPath: \.tint, range: Self.balanceRange),
                .init(title: String(localized: "Color", bundle: .module), keyPath: \.color, range: Self.balanceRange),
            ]
        case .texture:
            return [
                .init(title: String(localized: "Grain", bundle: .module), keyPath: \.grain, range: Self.amountRange),
                .init(title: String(localized: "Halation", bundle: .module), keyPath: \.halation, range: Self.amountRange),
            ]
        }
    }
}

/// One adjustment: its editable value, range and display units.
public struct AdjustmentControl: Identifiable {
    enum Unit { case stops, amount, temperature, whiteBalanceTint }

    public let title: String
    /// What VoiceOver calls it: the title, unless another group has a control of the same title.
    public let accessibilityLabel: String
    public let keyPath: WritableKeyPath<Adjustments, Double>
    public let range: ClosedRange<Double>
    let unit: Unit

    /// Unique across groups, which the title isn't: both tints are titled "Tint".
    public var id: String { accessibilityLabel }

    init(
        title: String, accessibilityLabel: String? = nil, keyPath: WritableKeyPath<Adjustments, Double>, range: ClosedRange<Double>,
        unit: Unit = .amount
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.keyPath = keyPath
        self.range = range
        self.unit = unit
    }

    /// A visible ruler tick and an accessible adjustment step.
    public var increment: Double {
        switch unit {
        case .stops: 0.1
        case .amount: 0.01
        case .temperature: TemperatureScale.increment
        case .whiteBalanceTint: AdjustmentGroup.whiteBalanceTintIncrement
        }
    }

    private static let signedInteger = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        .sign(strategy: .always(includingZero: false))

    /// Kelvin readouts are rounded to this: finer digits would suggest a precision the as-shot
    /// estimate doesn't have.
    private static let kelvinRounding = 10.0

    /// The value as VoiceOver speaks it: the readout, with a temperature's unit spelled out.
    public func accessibilityValue(_ value: Double) -> String {
        guard unit == .temperature else { return formatted(value) }
        return String(localized: "\(roundedKelvin(value)) kelvin", bundle: .module, comment: "Spoken colour temperature, e.g. 5,600 kelvin")
    }

    private func roundedKelvin(_ rulerValue: Double) -> String {
        ((TemperatureScale.kelvin(rulerValue: rulerValue) / Self.kelvinRounding).rounded() * Self.kelvinRounding)
            .formatted(.number.precision(.fractionLength(0)))
    }

    /// The value with a sign, e.g. "+0.7 EV" or "-35"; a temperature in kelvin, e.g. "5,600 K".
    public func formatted(_ value: Double) -> String {
        switch unit {
        case .temperature:
            return String(localized: "\(roundedKelvin(value)) K", bundle: .module, comment: "Colour temperature in kelvin, e.g. 5,600 K")
        case .whiteBalanceTint: return value.formatted(Self.signedInteger)
        case .stops:
            let stops = value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            return String(localized: "\(stops) EV", bundle: .module, comment: "Exposure in stops, e.g. +0.7 EV")
        case .amount: return (value * 100).formatted(Self.signedInteger)
        }
    }
}
