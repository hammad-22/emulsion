import EmulsionCore
import Foundation

/// The editor's controls, grouped the way the film process is: exposure and local tone, the
/// RAW develop's white balance, printer lights and color density, then texture. Shared so iOS
/// and Mac show the same controls with the same ranges; the iPhone panel shows one group at a time.
/// The digicam process uses the same controls, two of them under its own names
/// (`AdjustmentControl.title(for:)`).
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
                .init(
                    title: String(localized: "Grain", bundle: .module), digicamTitle: String(localized: "Noise", bundle: .module),
                    keyPath: \.grain, range: Adjustments.grainRange(for: .film), digicamRange: Adjustments.grainRange(for: .digicam)),
                .init(
                    title: String(localized: "Halation", bundle: .module), digicamTitle: String(localized: "Processing", bundle: .module),
                    keyPath: \.halation, range: Self.amountRange),
            ]
        }
    }
}

/// One adjustment: its editable value, range and display units.
public struct AdjustmentControl: Identifiable {
    enum Unit { case stops, amount, temperature, whiteBalanceTint }

    /// The film process's title, and VoiceOver's label: the title, unless another group has a
    /// control of the same title.
    private let filmTitle: String
    private let filmAccessibilityLabel: String
    /// The title in the digicam process when it differs (Grain is sensor noise, Halation the
    /// in-camera processing: fringing, lens, sharpening and JPEG).
    private let digicamTitle: String?
    public let keyPath: WritableKeyPath<Adjustments, Double>
    private let filmRange: ClosedRange<Double>
    /// The range in the digicam process when it differs (its Noise stops at 1, film grain at 2).
    private let digicamRange: ClosedRange<Double>?
    let unit: Unit

    /// Unique across groups, which the title isn't (both tints are titled "Tint"), and the same in
    /// every process, so a selection survives switching process.
    public var id: String { filmAccessibilityLabel }

    init(
        title: String, accessibilityLabel: String? = nil, digicamTitle: String? = nil, keyPath: WritableKeyPath<Adjustments, Double>,
        range: ClosedRange<Double>, digicamRange: ClosedRange<Double>? = nil, unit: Unit = .amount
    ) {
        self.filmTitle = title
        self.filmAccessibilityLabel = accessibilityLabel ?? title
        self.digicamTitle = digicamTitle
        self.keyPath = keyPath
        self.filmRange = range
        self.digicamRange = digicamRange
        self.unit = unit
    }

    /// What the control is called in `process`.
    public func title(for process: RenderProcess) -> String {
        switch process {
        case .film: filmTitle
        case .digicam: digicamTitle ?? filmTitle
        }
    }

    /// The values the control spans in `process`, which `Adjustments.clamped()` enforces.
    public func range(for process: RenderProcess) -> ClosedRange<Double> {
        switch process {
        case .film: filmRange
        case .digicam: digicamRange ?? filmRange
        }
    }

    /// What VoiceOver calls the control in `process`.
    public func accessibilityLabel(for process: RenderProcess) -> String {
        switch process {
        case .film: filmAccessibilityLabel
        case .digicam: digicamTitle ?? filmAccessibilityLabel
        }
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
